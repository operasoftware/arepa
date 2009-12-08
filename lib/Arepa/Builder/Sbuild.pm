package Arepa::Builder::Sbuild;

use strict;
use warnings;

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

my $last_build_log = undef;
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

sub _compile_package_from_spec {
    my ($self, $builder_name, $package_spec, $result_dir) = @_;

    if ($self->builder_exists($builder_name)) {
        my $tmp_dir = File::Temp::tempdir();
        my $initial_dir = Cwd::cwd;
        chdir $tmp_dir;

        my $build_cmd = "sbuild --chroot $builder_name --apt-update --nolog $package_spec &>/dev/null";
        my $r = system($build_cmd);
        # The build log is in the file (symlink really) 'current'
        if (open F, "current") {
            $last_build_log = join("", <F>);
            close F;
        }
        else {
            $last_build_log = undef;
        }

        # Move result to the result directory
        find({ wanted => sub {
                    if ($File::Find::name =~ /\.deb$/) {
                        move($File::Find::name, $result_dir);
                    }
               },
               follow => 0 },
             $tmp_dir);

        chdir $initial_dir;
        return ($r == 0);
    }
    else {
        croak "Don't know anything about builder '$builder_name'\n";
    }
}

sub do_compile_package_from_dsc {
    my ($self, $builder_name, $dsc_file, $result_dir) = @_;
    return $self->_compile_package_from_spec($builder_name,
                                             $dsc_file,
                                             $result_dir);
}

sub do_compile_package_from_repository {
    my ($self, $builder_name, $pkg_name, $pkg_version, $result_dir) = @_;
    my $package_spec = $pkg_name . '_' . $pkg_version;

    return $self->_compile_package_from_spec($builder_name,
                                             $package_spec,
                                             $result_dir);
}

sub do_create {
    my ($self, $builder_dir, $mirror, $distribution) = @_;

    my $builder_name = basename($builder_dir);

    my $schroot_file = "/etc/schroot/chroot.d/$builder_name";
    if (-e $schroot_file) {
        print STDERR "Builder $builder_name already exists ($schroot_file)\n";
        exit 1;
    }
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
#personality=linux32"
EOCONTENT
    $self->ui_module->print_info("Creating schroot file ($schroot_file)");
    if (open F, ">$schroot_file") {
        print F $schroot_content;
        close F;
    }
    else {
        print STDERR "Couldn't write to file $schroot_file. Check permissions\n";
        print STDERR "This is the content that should be in it:\n";
        print STDERR "---------------------- 8< ----------------------\n";
        print STDERR $schroot_content;
        print STDERR "---------------------- >8 ----------------------\n";
    }

    $self->ui_module->print_info("Creating base chroot");
    my $debootstrap_cmd = "debootstrap --variant=buildd $distribution '$builder_dir' $mirror";
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
deb http://localhost/arepa-repository $distribution main
deb-src http://localhost/arepa-repository $distribution main
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

    $self->ui_module->print_info("Installing build-essential and fakeroot");
    my $cmd = "chroot '$builder_dir' apt-get -y --force-yes install " .
                                                "build-essential fakeroot";
    return system($cmd);
}

1;
