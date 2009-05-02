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
