package Arepa::Web::Base;

use strict;
use warnings;

use base 'Mojolicious::Controller';

use Arepa::Config;

my @conffiles = qw(/etc/arepa/config.yml);
our $config      = undef;
our $config_path = undef;
foreach my $conffile (@conffiles) {
    if (-r $conffile) {
        $config_path = $conffile;
        $config = Arepa::Config->new($config_path);
        last ;
    }
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
