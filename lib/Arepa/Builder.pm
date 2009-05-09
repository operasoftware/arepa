package Arepa::Builder;

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

my $ui_module      = 'Arepa::UI::Text';

sub ui_module {
    my ($self, $module) = @_;
    if (defined $module) {
        $ui_module = $module;
    }
    eval qq(use $ui_module;);
    return $ui_module;
}


# To be implemented by each type

sub init {
    my ($self, $builder) = @_;
    croak "Not implemented";
}

sub compile_package_from_dsc {
    my ($self, $builder_name, $dsc_file, $result_dir) = @_;

    croak "Not implemented";
}

sub compile_package_from_repository {
    my ($self, $builder_name, $pkg_name, $pkg_version, $result_dir) = @_;

    croak "Not implemented";
}

sub last_build_log {
    return;
}

sub create {
    my ($self, $builder_dir, $mirror, $distribution) = @_;

    croak "Not implemented";
}

1;
