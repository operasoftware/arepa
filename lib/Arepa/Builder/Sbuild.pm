package Arepa::Builder::Sbuild;

use strict;
use warnings;

use English qw(-no_match_vars);
use Carp;
use Cwd;
use File::chmod;
use File::Temp;
use File::Basename;
use File::Path;
use File::Find;
use File::Copy;
use Config::Tiny;
use YAML::Syck;

use Arepa;

use base qw(Arepa::Builder);

our $last_build_log = undef;
my $schroot_config = undef;

sub last_build_log {
    return $last_build_log;
}

sub _get_schroot_conf {
    my ($self) = @_;

    if (!defined $schroot_config) {
        my $content = "";
        for my $path ('/etc/schroot/schroot.conf', glob('/etc/schroot/chroot.d/*')) {
            if (open F, $path) {
                $content .= join("", <F>) . "\n";
                close F;
            }
            else {
                print STDERR "Ignoring file '$path': couldn't read\n";
            }
        }
        $schroot_config = Config::Tiny->read_string($content);
    }

    return $schroot_config;
}

sub ensure_file_exists {
    my ($self, $path) = @_;

    unless (-e $path) {
        open F, ">$path" or croak "Couldn't create file '$path'\n";
        close F;
    }
}

sub builder_exists {
    my ($self, $builder_name) = @_;

    return (defined $self->_get_schroot_conf->{$builder_name});
}

sub get_builder_directory {
    my ($self, $builder_name) = @_;

    if ($self->builder_exists($builder_name)) {
        return $self->_get_schroot_conf->{$builder_name}->{location};
    }
    else {
        croak "Can't find schroot information for builder '$builder_name'\n";
    }
}

sub do_init {
    my ($self, $builder) = @_;

    my $builder_dir = $self->get_builder_directory($builder);

    # Bind some important files to the 'host'
    foreach my $etc_file (qw(resolv.conf passwd shadow group gshadow)) {
        my $full_path = "$builder_dir/etc/$etc_file";
        unless (-e $full_path) {
            $self->ensure_file_exists($full_path);
        }
        my $mount_cmd = qq(mount -oro,bind "/etc/$etc_file" "$full_path");
        $self->ui_module->print_info("Binding /etc/$etc_file to $full_path");
        system($mount_cmd);
    }
}

sub do_uninit {
    my ($self, $builder) = @_;

    my $builder_dir = $self->get_builder_directory($builder);

    # Bind some important files to the 'host'
    my $ok = 1;
    foreach my $etc_file (qw(resolv.conf passwd shadow group gshadow)) {
        my $full_path = "$builder_dir/etc/$etc_file";
        $self->ui_module->print_info("Unbinding $full_path from /etc/$etc_file");
        my $r = system(qq(umount "$full_path" 2>/dev/null));
        if ($r != 0) {
            $ok = 0;
        }
    }
    return $ok;
}

sub _compile_package_from_spec {
    my ($self, $builder_name, $package_spec, %user_opts) = @_;
    my %opts = (output_dir => '.', bin_nmu => 0, %user_opts);

    if ($self->builder_exists($builder_name)) {
        my $tmp_dir = File::Temp::tempdir();
        my $initial_dir = Cwd::cwd;
        chdir $tmp_dir;

        my $extra_opts = "";
        if ($opts{bin_nmu}) {
            $extra_opts .= " --make-binNMU='Recompiled by Arepa' " .
                            "--binNMU='$opts{bin_nmu}' " .
                            "--uploader='Arepa <arepa-master\@localhost>'";
        }

        my $build_cmd = "sbuild --chroot $builder_name --apt-update --nolog -A $package_spec $extra_opts";
        $last_build_log = qx/$build_cmd/;
        my $r = $CHILD_ERROR;

        # Move result to the result directory
        chdir $initial_dir;
        my $output_dir = $opts{output_dir};
        # Relative path?
        if ($output_dir !~ qr,^/,) {
            $output_dir = File::Spec->catfile($initial_dir, $opts{output_dir});
        }
        find({ wanted => sub {
                    if ($File::Find::name =~ /\.deb$/) {
                        my $r = move($File::Find::name, $output_dir);
                        if (!$r) {
                            print STDERR "Couldn't move $File::Find::name to $output_dir.\nCan't write to $output_dir maybe?\n";
                        }
                    }
               },
               follow => 0 },
             $tmp_dir);
        # Remove temporary directory
        rmtree($tmp_dir);

        return ($r == 0);
    }
    else {
        croak "Don't know anything about builder '$builder_name'\n";
    }
}

sub do_compile_package_from_dsc {
    my ($self, $builder_name, $dsc_file, %user_opts) = @_;
    my %opts = (output_dir => '.', %user_opts);
    return $self->_compile_package_from_spec($builder_name,
                                             $dsc_file,
                                             %opts);
}

sub do_compile_package_from_repository {
    my ($self, $builder_name, $pkg_name, $pkg_version, %user_opts) = @_;
    my %opts = (output_dir => '.', %user_opts);
    my $package_spec = $pkg_name . '_' . $pkg_version;

    return $self->_compile_package_from_spec($builder_name,
                                             $package_spec,
                                             %opts);
}

sub do_create {
    my ($self, $builder_dir, $mirror, $distribution, %opts) = @_;

    my $builder_name = basename($builder_dir);

    my $chrootd_dir = "/etc/schroot/chroot.d";
    my $schroot_file = "$chrootd_dir/$builder_name";
    if (-e $schroot_file) {
        print STDERR "Builder $builder_name already exists ($schroot_file)\n";
        exit 1;
    }
    mkpath $chrootd_dir;
    my $schroot_content = <<EOCONTENT;
[$builder_name]
description=Arepa autobuilder $builder_name
location=$builder_dir
priority=3
root-groups=sbuild
# groups=sbuild-security
groups=sbuild
#aliases=testing
run-setup-scripts=false
run-exec-scripts=false
#personality=linux32
EOCONTENT
    $self->ui_module->print_info("Creating schroot file ($schroot_file)");
    if (open F, ">$schroot_file") {
        print F $schroot_content;
        close F;
    }
    else {
        print STDERR "Couldn't write to file $schroot_file. Check permissions\n";
        exit 1;
    }

    $self->ui_module->print_info("Creating base chroot");
    my $extra_opts = "";
    if (defined $opts{arch}) {
        $extra_opts .= " --arch $opts{arch}";
    }
    my $debootstrap_cmd = "debootstrap --variant=buildd $extra_opts " .
                            "$distribution '$builder_dir' $mirror";
    my $r = system($debootstrap_cmd);
    if ($r != 0) {
        print STDERR "Error executing debootstrap: error code $r\n";
        print STDERR $debootstrap_cmd, "\n";
        unlink $schroot_file;
        exit 1;
    }

    # Create appropriate /etc/apt/sources.list
    $self->ui_module->print_info("Creating default sources.list");
    open SOURCESLIST, ">$builder_dir/etc/apt/sources.list" or
        do {
            print STDERR "Couldn't write to /etc/apt/sources.list";
            exit 1;
        };
    print SOURCESLIST <<EOSOURCES;
deb $mirror $distribution main
deb http://localhost/arepa/repository $distribution main
deb-src http://localhost/arepa/repository $distribution main
EOSOURCES
    close SOURCESLIST;

    # Making sure /etc/hosts includes localhost
    $self->ui_module->print_info("Checking /etc/hosts");
    my $full_etc_hosts_path = "$builder_dir/etc/hosts";
    $self->ensure_file_exists($full_etc_hosts_path);
    if (open F, $full_etc_hosts_path) {
        my $contents = join("", <F>);
        close F;
        if (! grep /localhost/, $contents) {
            if (open F, ">$full_etc_hosts_path") {
                print F $contents, "\n";
                print F "127.0.0.1\tlocalhost\n";
                close F;
            }
            else {
                print STDERR "Couldn't update $full_etc_hosts_path\n";
            }
        }
    }
    else {
        print STDERR "Couldn't check for a 'localhost' alias in $full_etc_hosts_path\n";
    }

    # Make sure certain directories exist and are writable by the 'sbuild'
    # group
    $self->ui_module->print_info("Creating build directories");
    my ($login, $pass, $uid, $gid) = getpwnam($Arepa::AREPA_MASTER_USER);
    if (!defined $login) {
        croak "'" . $Arepa::AREPA_MASTER_USER . "' user doesn't exist!";
    }
    foreach my $dir (qw(build var/lib/sbuild var/lib/sbuild/srcdep-lock)) {
        my $full_path = "$builder_dir/$dir";
        unless (-d $full_path) {
            mkpath $full_path;
            find({ wanted => sub {
                        chmod("g+w", $File::Find::name);
                        chown $uid, $gid, $File::Find::name;
                   },
                   follow => 0 },
                 $full_path);
        }
    }

    $self->ui_module->print_info("Binding files");
    Arepa::Builder::Sbuild->init($builder_name);

    $self->ui_module->print_info("Updating package list");
    my $update_cmd = "chroot '$builder_dir' apt-get update";
    system($update_cmd);

    $self->ui_module->print_info("Installing build-essential and fakeroot");
    my $install_cmd = "chroot '$builder_dir' apt-get -y --force-yes install " .
                                                "build-essential fakeroot";
    return system($install_cmd);
}

1;

__END__

=head1 AUTHOR

Esteban Manchado Velázquez <estebanm@opera.com>.

=head1 LICENSE AND COPYRIGHT

This code is offered under the Open Source BSD license.

Copyright (c) 2010, Opera Software. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

=over 4

=item

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

=item

Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

=item

Neither the name of Opera Software nor the names of its contributors may
be used to endorse or promote products derived from this software without
specific prior written permission.

=back

=head1 DISCLAIMER OF WARRANTY

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
