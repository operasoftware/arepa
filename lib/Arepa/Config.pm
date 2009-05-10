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

__END__

=head1 NAME

Arepa::Config - Arepa package database API

=head1 SYNOPSIS

 my $config = Arepa::Config->new('path/to/config.yml');
 my $pdb_path = $config->get_key('package_db');
 my $repo_path = $config->get_key('repository:path');
 my @builder_names = $config->get_builders;
 my %builder_config = $config->get_builder_config('some-builder');
 my $value = $config->get_builder_config_key('some-builder', $key);

=head1 DESCRIPTION

This class allows easy access to the Arepa configuration. The configuration is
stored in a YAML file, and these are the structure for it:

 ---
 repository:
   path: /home/zoso/src/apt-web/test-repo/
 upload_queue:
   path: /home/zoso/src/apt-web/incoming
 package_db: /home/zoso/src/apt-web/package.db
 web_ui:
   base_url: http://localhost
   template_dir: /home/zoso/src/apt-web/repo-tools-web/templates/
   user_file: /home/zoso/src/apt-web/repo-tools-web/users.yml
 builders:
   - name: squeeze32
     type: sbuild
     architecture: i386
     distribution: my-squeeze
     other_distributions: [squeeze, unstable]
   - name: squeeze64
     type: sbuild
     architecture: amd64
     architecture_all: yes
     distribution: my-squeeze
     other_distributions: [squeeze, unstable]

Usually this class is not used directly, but internally in C<Arepa::Repository>
or C<Arepa::BuilderFarm>.

=head1 METHODS

=over 4

=item new($path)

It creates a new configuration access object for the configuration file in the
given C<$path>.

=item get_key($key)

Returns the value of the given C<$key> in the configuration file. If it's not a
top-level key, the subkeys must be separated by a colon ("C<:>"). If the key
cannot be found, an exception is thrown.

=item get_builders

Returns an array of names of the defined builders.

=item get_builder_config($builder_name)

Returns a hash with the configuration of the given C<$builder_name>. If no
builder (or more than one) is found by that name, an exception is thrown.

=item get_builder_config_key($builder_name, $key)

Returns the value for the given configuration C<$key> for the given
C<$builder_name>.

=back
