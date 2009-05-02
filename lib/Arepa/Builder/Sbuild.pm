package Arepa::Builder::Sbuild;

use Carp;
use Cwd;
use File::Temp;
use Config::Tiny;

my $last_build_log = undef;
my $schroot_config = undef;

sub get_schroot_conf {
    my ($self) = @_;

    if (!defined $schroot_config) {
        my $content = "";
        for my $path ('/etc/schroot/schroot.conf', glob('/etc/schroot/chroot.d/*')) {
            if (open F, $path) {
                $content .= join("", <F>);
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

sub builder_exists {
    my ($self, $builder_name) = @_;

    my $schroot_conf = $self->get_schroot_conf;
    return (defined $schroot_conf->{$builder_name});
}

sub get_builder_directory {
    my ($self, $builder_name) = @_;

    if ($self->builder_exists($builder_name)) {
        return $schroot_conf->{$builder_name}->{location};
    }
    else {
        croak "Can't find schroot information for builder '$builder_name'\n";
    }
}

sub init_builder {
    my ($self, $builder) = @_;

    my $builder_dir = $self->get_builder_directory($builder);

    # Bind some important files to the 'host'
    foreach my $etc_file (qw(resolv.conf passwd shadow group gshadow)) {
        my $full_path = "$builder_dir/etc/$etc_file";
        unless (-e $full_path) {
            my $atime = time;
            utime $atime, $atime, $full_path;
        }
        system(qq(mount -oro,bind "/etc/$etc_file" "$full_path"));
    }
}

# $package_spec can be either the path to a .dsc file or a <package>_<version>
# XXX TODO: this should have a different API so it's easy to create other kinds
# of builder
sub compile_package {
    my ($self, $builder_name, $package_spec, $result_dir) = @_;

    if ($self->builder_exists($builder_name)) {
        my $tmp_dir = File::Temp::tempdir();
        my $initial_dir = Cwd::cwd;
        chdir $tmp_dir;

        my $build_cmd = "sbuild --chroot $builder_name --nolog $package_spec &>/dev/null";
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

sub last_build_log {
    return $last_build_log;
}

1;
