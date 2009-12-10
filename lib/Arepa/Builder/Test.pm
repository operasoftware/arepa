package Arepa::Builder::Test;

use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;

use Arepa;

use base qw(Arepa::Builder);

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
    open F, ">$opts{output_dir}/$basename$extra_version\_all.deb";
    print F "Fake contents of the package\n";
    close F;
    return 1;
}

sub do_compile_package_from_repository {
    my ($self, $builder_name, $package, $version, %user_opts) = @_;
    my %opts = (output_dir => '.', %user_opts);

    my $extra_version = $opts{bin_nmu} ? "+b1" : "";
    open F, ">$opts{output_dir}/$package\_$version$extra_version\_all.deb";
    print F "Fake contents of the package\n";
    close F;
    return 1;
}

sub do_create {
    my ($self, $builder_dir, $mirror, $distribution) = @_;
    return 1;
}

1;
