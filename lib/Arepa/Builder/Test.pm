package Arepa::Builder::Test;

use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;

use Arepa;

use base qw(Arepa::Builder);

our $last_build_log = undef;
sub last_build_log {
    return $last_build_log;
}

sub do_init {
    my ($self, $builder) = @_;
    return 1;
}

sub do_compile_package_from_dsc {
    my ($self, $builder_name, $dsc_file, %user_opts) = @_;
    my %opts = (output_dir => '.', %user_opts);

    my $basename = basename($dsc_file);
    $basename =~ s/\.dsc$//go;
    my $extra_version = $opts{bin_nmu} ? "+b1" : "";
    my $package_file_name = "$basename$extra_version\_all.deb";
    open F, ">$opts{output_dir}/$package_file_name";
    print F "Fake contents of the package\n";
    close F;
    $last_build_log = "Building $package_file_name. Not.\n";
    return 1;
}

sub do_compile_package_from_repository {
    my ($self, $builder_name, $package, $version, %user_opts) = @_;
    my %opts = (output_dir => '.', %user_opts);

    my $extra_version = $opts{bin_nmu} ? "+b1" : "";
    my $package_file_name = "$package\_$version$extra_version\_all.deb";
    open F, ">$opts{output_dir}/$package_file_name";
    print F "Fake contents of the package\n";
    close F;
    $last_build_log = "Building $package_file_name. Not.\n";
    return 1;
}

sub do_create {
    my ($self, $builder_dir, $mirror, $distribution) = @_;
    return 1;
}

1;
