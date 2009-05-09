package Arepa::Builder::Test;

use strict;
use warnings;

use Carp;
use Cwd;
use File::Basename;

use Arepa;

use base qw(Arepa::Builder);

sub init {
    my ($self, $builder) = @_;
    return 1;
}

sub compile_package_from_dsc {
    my ($self, $builder_name, $dsc_file, $result_dir) = @_;
    my $basename = basename($dsc_file);
    $basename =~ s/\.dsc$//go;
    open F, ">$result_dir/$basename\_all.deb";
    print F "Fake contents of the package\n";
    close F;
    return 1;
}

sub compile_package_from_repository {
    my ($self, $builder_name, $package, $version, $result_dir) = @_;
    open F, ">$result_dir/$package\_$version\_all.deb";
    print F "Fake contents of the package\n";
    close F;
    return 1;
}

sub create {
    my ($self, $builder_dir, $mirror, $distribution) = @_;
    return 1;
}

1;
