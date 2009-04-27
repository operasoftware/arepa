package Arepa::Config;

use Carp qw(croak);
use YAML::Syck;

sub new {
    my ($class, $path) = @_;

    my $self = bless {
        config => LoadFile($path),
    }, $class;

    return $self;
}

sub get_key {
    my ($self, $key) = @_;

    my @keys = split(':', $key);
    my $value = $self->{config};
    foreach my $k (@keys) {
        if (defined $value->{$k}) {
            $value = $value->{$k};
        }
        else {
            croak "Can't find configuration key $key (no $k)";
        }
    }
    return $value;
}

sub get_builders {
    my ($self, %user_opts) = @_;
    my %opts = (%user_opts);

    my @builders = @{$self->{config}->{builders}};
    if (exists $opts{type}) {
        @builders = grep { $_->{type} eq $opts{type} }
                         @builders;
    }
    return map { $_->{name} } @builders;
}

sub get_builder_config {
    my ($self, $builder_name) = @_;

    my $builder_config = $self->{config}->{builders};
    my @matching_builders = grep { $_->{name} eq $builder_name }
                                 @$builder_config;
    scalar(@matching_builders) == 0 and
        croak "Don't know builder '$builder_name'";
    scalar(@matching_builders) >  1 and
        croak "There is more than one builder called '$builder_name'";
    return %{$matching_builders[0]};
}

sub get_builder_config_key {
    my ($self, $builder_name, $config_key) = @_;

    my $builder_config = $self->get_builder_config($builder_name);
    defined($builder_config->{$config_key}) or
        croak "'$builder_name' doesn't have a configuration key $config_key";
    return $builder_config->{$config_key};
}

1;
