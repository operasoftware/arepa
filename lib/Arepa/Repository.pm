package Arepa::Repository;

use strict;
use warnings;

use Carp qw(croak);

use Arepa::Config;
use Arepa::PackageDb;

sub new {
    my ($class, $config_path) = @_;

    my $config = Arepa::Config->new($config_path);
    my $self = bless {
        config_path => $config_path,
        config      => $config,
        package_db  => Arepa::PackageDb->new($config->get_key('package_db')),
    }, $class;

    return $self;
}

sub get_config_key {
    my ($self, $key) = @_;
    return $self->{config}->get_key($key);
}

sub get_repositories {
    my ($self, $key) = @_;

    my $repository_config_file = $self->get_config_key('repository:path');
    my $distributions_config_file = "$repository_config_file/conf/distributions";
    open F, $distributions_config_file or croak "Can't open configuration file ";
    my ($line, $repo_attrs, @repos);
    while ($line = <F>) {
        if ($line =~ /^\s*$/) {
            use Data::Dumper;
            push @repos, $repo_attrs if %$repo_attrs;
            $repo_attrs = {};
        }
        elsif ($line =~ /^([^:]+):\s+(.+)/i) {
            $repo_attrs->{lc($1)} = $2;
        }
    }
    push @repos, $repo_attrs if %$repo_attrs;
    close F;
    return @repos;
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

    # Handle special "any" case with the architecture
    my @archs = ($arch);
    if ($arch eq 'any') {
        @archs = $self->get_repository_architectures;
    }

    # Get the builder information once
    my @builder_information = map { { $self->{config}->get_builder_config($_) } }
                                  $self->{config}->get_builders;

    # Get builders that match *both*:
    return map {
                $_->{name}
           }
           # 1) the architecture in 'architecture' (or 'all' if applicable)
           grep {
               my $bi      = $_;
               my @barchs  = $bi->{architecture};
               if ($bi->{architecture_all}) {
                   push @barchs, 'all';
               }
               my $matches = 0;
               foreach my $a (@archs) {
                   if (grep { $a eq $_ } @barchs) {
                       $matches = 1;
                   }
               }
               $matches;
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

sub get_repository_architectures {
    my ($self) = @_;

    my @archs;
    foreach my $repo ($self->get_repositories) {
        foreach my $arch (split(/\s+/, $repo->{architectures})) {
            push @archs, $arch unless grep { $arch eq $_ }
                                           @archs;
        }
    }
    return @archs;
}

sub insert_source_package {
    my ($self, @args) = @_;
    $self->{package_db}->insert_source_package(@args);
}

1;
