package Arepa::BuilderFarm;

use strict;
use warnings;

use Carp qw(croak);
use Cwd;
use File::Temp;

use Arepa::Config;
use Arepa::PackageDb;

sub new {
    my ($class, $config_path, %user_opts) = @_;

    my $config = Arepa::Config->new($config_path, %user_opts);
    my $self = bless {
        config_path => $config_path,
        config      => $config,
        package_db  => Arepa::PackageDb->new($config->get_key('package_db')),
        last_build_log => undef,
    }, $class;

    return $self;
}

sub last_build_log {
    my ($self) = @_;
    return $self->{last_build_log};
}

sub package_db {
    my ($self) = @_;
    return $self->{package_db};
}

sub get_builder_config {
    my ($self, $builder) = @_;
    return $self->{config}->get_builder_config($builder);
}

sub builder_type_module {
    my ($self, $type) = @_;
    $type =~ s/[^a-z0-9]//goi;
    return "Arepa::Builder::" . ucfirst(lc($type));
}

sub builder_module {
    my ($self, $builder) = @_;
    my %conf = $self->get_builder_config($builder);
    my $module = $self->builder_type_module($conf{type});
    eval "use $module;";
    if ($@) {
        croak "Couldn't load builder module '$module' for type '$conf{type}': $@";
    }
    return $module;
}

sub init_builders {
    my ($self) = @_;

    foreach my $builder ($self->{config}->get_builders) {
        $self->init_builder($builder);
    }
}

sub init_builder {
    my ($self, $builder) = @_;

    my $module = $self->builder_module($builder);
    $module->init($builder);
}

sub compile_package_from_dsc {
    my ($self, $builder, $dsc_file, $result_dir) = @_;
    $result_dir ||= '.';

    my $module = $self->builder_module($builder);
    my $r = $module->compile_package_from_dsc($builder,
                                              $dsc_file,
                                              $result_dir);
    $self->{last_build_log} = $module->last_build_log;
    return $r;
}

sub compile_package_from_queue {
    my ($self, $builder, $request_id, $result_dir) = @_;
    $result_dir ||= '.';

    my %request = $self->package_db->get_compilation_request_by_id($request_id);
    $self->package_db->mark_compilation_started($request_id, $builder);

    my $module = $self->builder_module($builder);
    my %source_attrs = $self->package_db->get_source_package_by_id($request{source_package_id});
    my $r = $module->compile_package_from_repository(
                                            $builder,
                                            $source_attrs{name},
                                            $source_attrs{full_version},
                                            $result_dir);
    $self->{last_build_log} = $module->last_build_log;
    if ($r) {
        $self->package_db->mark_compilation_completed($request_id);
    }
    else {
        $self->package_db->mark_compilation_failed($request_id);
    }
    return $r;
}

sub request_package_compilation {
    my ($self, $source_id) = @_;

    foreach my $target ($self->get_compilation_targets($source_id)) {
        my ($arch, $dist) = @$target;
        $self->{package_db}->request_compilation($source_id, $arch, $dist);
    }
}

sub get_compilation_targets {
    my ($self, $source_id) = @_;

    my %source_attrs = $self->{package_db}->get_source_package_by_id($source_id);
    my @builders = $self->get_matching_builders($source_attrs{architecture},
                                                $source_attrs{distribution});
    return map {
               my %builder_config = $self->{config}->get_builder_config($_);
               $source_attrs{architecture} eq 'any' ?
                   [$builder_config{architecture},
                    $builder_config{distribution}]  :
                   [$source_attrs{architecture},
                    $builder_config{distribution}];
           } @builders;
}

sub get_matching_builders {
    my ($self, $arch, $distro) = @_;

    # Get the builder information once
    my @builder_information = map { { $self->{config}->get_builder_config($_) } }
                                  $self->{config}->get_builders;

    # Get builders that match *both*:
    return map {
                $_->{name}
           }
           # 1) the architecture in 'architecture' (or 'all' if applicable)
           grep {
               ($arch eq 'any'                            ||
                $arch eq $_->{architecture}               ||
                ($arch eq 'all' && $_->{architecture_all}));
           }
           # 2) the $distro in *either* 'distribution' or
           #    'other_distributions'
           grep {
               my @bdistros = ref($_->{other_distributions}) eq 'ARRAY' ?
                                   @{$_->{other_distributions}} :
                                   $_->{other_distributions};

               $distro eq $_->{distribution} ||
                   grep { $distro eq $_ } @bdistros;
           }
           @builder_information;
}

sub register_source_package {
    my ($self, %source_attrs) = @_;

    my $pdb = $self->package_db;
    my $source_id = $pdb->get_source_package_id($source_attrs{name},
                                                $source_attrs{full_version});
    if (!defined $source_id) {
        $source_id = $pdb->insert_source_package(%source_attrs);
    }
    return $source_id;
}

1;

__END__

=head1 NAME

Arepa::BuilderFarm - Arepa builder farm access class

=head1 SYNOPSIS

 my $repo = Arepa::BuilderFarm->new('path/to/config.yml');
 my $repo = Arepa::BuilderFarm->new('path/to/config.yml',
                                    builder_config_dir =>
                                                    'path/to/builderconf');
 $repo->last_build_log;
 $repo->package_db;

 my %config = $repo->get_builder_config($builder_name);
 my $module_name = $repo->builder_type_module($type);
 my $module_name = $repo->builder_module($builder_name);

 $repo->init_builders;
 $repo->init_builder($builder_name);

 my $r = $repo->compile_package_from_dsc($builder_name,
                                         $dsc_file,
                                         $dir);
 my $r = $repo->compile_package_from_queue($builder_name,
                                           $request_id,
                                           $dir);

 $repo->request_package_compilation($source_id);
 my @arch_distro_pairs = $repo->get_compilation_targets($source_id);
 my @builders = $repo->get_matching_builders($architecture,
                                             $distribution);

 my $source_id = $repo->register_source_package(%source_package_attrs);

=head1 DESCRIPTION

This class gives access to the "builder farm", to actions like initialising the
builders, compiling packages and calculating which builders should compile
which packages.

The builder farm uses the Arepa configuration to get the needed information.

=head1 METHODS

=over 4

=item new($path)

=item new($path, %options)

Creates a new builder farm access object, using the configuration file in
C<$path>. The only valid option is C<builder_config_dir> (see L<Arepa::Config>
documentation for details).

=item last_build_log

Returns the output of the last compilation attempt.

=item package_db

Returns a C<Arepa::PackageDb> object pointing to the package database used by
the builder farm.

=item get_builder_config($builder_name)

Returns a has with the configuration for the builder C<$builder_name>.

=item builder_type_module($type)

Returns the module name implementing the features for the builder type
C<$type>.

=item builder_module($builder_name)

Returns the module name implementing the features for the given
C<$builder_name>.

=item init_builders

Initialises all the builders. It should be called once per machine boot (e.g.
inside an init script).

=item init_builder($builder_name)

Initialises the builder C<$builder_name>. It should be called once per machine
boot (e.g. inside an init script).

=item compile_package_from_dsc($builder_name, $dsc_file, $dir)

Compiles the source package described by the C<.dsc> file C<$dsc_file> using
the builder C<$builder_name>, and puts the resulting C<.deb> files in the given
C<$dir>. If a directory is not specified, they're left in the current
directory.

=item compile_package_from_queue($builder_name, $request_id, $dir)

Compiles the request C<$request_id> using the builder C<$builder_name>, and
puts the resulting C<.deb> files in the given C<$dir>. If a directory is not
specified, they're left in the current directory.

=item request_package_compilation($source_id)

Adds a compilation request for the source package with id C<$source_id>.

=item get_compilation_targets($source_id)

Returns an array of targets for the given source package C<$source_id>. Each
target is an arrayref with two elements: architecture and distribution.

=item get_matching_builders($architecture, $distribution)

Gets the builders that should compile packages for the given C<$architecture>
and C<$distribution>.

=item register_source_package(%source_package_attrs)

Registers the source package with the given C<%source_package_attrs>. This
method is seldom used, as you would normally add the source package to the
repository first (using C<Arepa::Repository>), which automatically registers
the source package.

=back

=head1 SEE ALSO

C<Arepa::Repository>, C<Arepa::PackageDb>, C<Arepa::Config>.
