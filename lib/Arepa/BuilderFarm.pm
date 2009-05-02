package Arepa::BuilderFarm;

use strict;
use warnings;

use Carp qw(croak);
use Cwd;
use File::Temp;

use Arepa::Config;
use Arepa::PackageDb;

sub new {
    my ($class, $config_path) = @_;

    my $config = Arepa::Config->new($config_path);
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
    $module->init_builder($builder);
}

sub compile_package {
    my ($self, $builder, $dsc_file, $result_dir) = @_;

    my $module = $self->builder_module($builder);
    my $r = $module->compile_package($builder, $dsc_file, $result_dir);
    $self->{last_build_log} = $module->last_build_log;
    return $r;
}

sub compile_package_from_queue {
    my ($self, $builder, $request_id, $result_dir) = @_;

    my %request = $self->package_db->get_compilation_request_by_id($request_id);
    $self->package_db->mark_compilation_started($request_id, $builder);

    my $module = $self->builder_module($builder);
    my %source_attrs = $self->package_db->get_source_package_by_id($request{source_package_id});
    my $r = $module->compile_package($builder,
                                     $source_attrs{name} . "_" .
                                        $source_attrs{full_version},
                                     $result_dir);
    if ($r) {
        $self->mark_compilation_completed($request_id);
    }
    else {
        $self->mark_compilation_failed($request_id);
    }
    return $r;
}

sub request_package_compilation {
    my ($self, $source_id) = @_;

    foreach my $target (get_compilation_targets($source_id)) {
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

1;
