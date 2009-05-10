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

my $ui_module = 'Arepa::UI::Text';

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

__END__

=head1 NAME

Arepa::Builder - Arepa builder base "class"

=head1 SYNOPSIS

 my $module = Arepa::Builder->ui_module;
 Arepa::Builder->ui_module($new_ui_module);

 Arepa::Builder->init($builder_name);

 Arepa::Builder->compile_package_from_dsc($builder_name, $dsc_file);
 Arepa::Builder->compile_package_from_dsc($builder_name, $dsc_file,
                                          $result_dir);
 Arepa::Builder->compile_package_from_repository($builder_name,
                                                 $dsc_file);
 Arepa::Builder->compile_package_from_repository($builder_name,
                                                 $dsc_file,
                                                 $result_dir);

 my $log = Arepa::Builder->last_build_log;

 Arepa::Builder->create($builder_dir, $mirror, $distribution);

=head1 DESCRIPTION

This module contains the interface for an Arepa builder. It should be the
"subclass" for any builder module. Every Arepa builder type must have a module
implementing this API. C<Arepa::BuilderFarm>, when manipulating the builders,
will use the correct builder module according to the builder type (e.g. for
type 'sbuild', C<Arepa::Builder::Sbuild>).

This module is never used directly, but through "subclasses" in
C<Arepa::BuilderFarm>.

=head1 METHODS

=over 4

=item ui_module

=item ui_module($ui_module)

Returns the UI module being used (by default, C<Arepa::UI::Text>. If a
parameter is passed, the UI module is changed to that, and the new value is
returned.

=item init($builder_name)

Initialises the given C<$builder_name> to be able to use it. This should be
done once per machine boot (e.g. in an init script).

=item compile_package_from_dsc($builder_name, $dsc_file)

=item compile_package_from_dsc($builder_name, $dsc_file, $result_dir)

Compiles the source package described by the given C<$dsc_file> using the given
C<$builder_name>. The resulting C<.deb> files are put in the given
C<$result_dir> (by default, the current directory).

=item compile_package_from_repository($builder_name, $name, $version)

=item compile_package_from_repository($builder_name, $name, $version, $dir)

Compiles the source package with the given C<$name> and C<$version> using the
given C<$builder_name>. The resulting C<.deb> files are put in the given
C<$result_dir> (by default, the current directory).

=item last_build_log

Returns the log text of the last build.

=item create($builder_dir, $mirror, $distribution);

Creates a new builder in the given directory C<$builder_dir>, using the Debian
mirror C<$mirror> and the distribution C<$distribution>.

=back

=head1 SEE ALSO

C<Arepa::BuilderFarm>, C<Arepa::Config>.
