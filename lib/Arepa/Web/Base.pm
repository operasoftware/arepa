package Arepa::Web::Base;

use strict;
use warnings;

use base 'Mojolicious::Controller';

use Arepa::Config;

my $DEFAULT_CONFIG_PATH = '/etc/arepa/config.yml';
our $config      = undef;
our $config_path = $ENV{AREPA_CONFIG} || $DEFAULT_CONFIG_PATH;

if (-r $config_path) {
    $config = Arepa::Config->new($config_path);
}
else {
    die "Couldn't read configuration file $config_path.\n" .
        "Use the environment variable AREPA_CONFIG to specify one.\n";
}

sub config      { return $Arepa::Web::Base::config; }
sub config_path { return $Arepa::Web::Base::config_path; }


sub _add_error {
    my ($self, $error, $output) = @_;
    push @{$self->{error_list}}, {error  => $error,
                                  output => $output || ""};
}

sub _error_list {
    my ($self) = @_;
    @{$self->{error_list} || []};
}

sub vars {
    my ($self, @args) = @_;

    $self->stash(
        base_url     => $self->config->get_key('web_ui:base_url'),
        is_synced    => undef,
        @args);
}

sub show_view {
    my ($self, $stash, %opts) = @_;

    $self->vars(%$stash);
    if ($opts{template}) {
        $self->render($opts{template}, layout => 'default');
    }
    else {
        $self->render(layout => 'default');
    }
}

1;
