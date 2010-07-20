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

sub _base_stash {
    my ($self) = @_;
    my %r = ();
    use Data::Dumper;
    print STDERR Dumper(\%r);
    return %r;
}

sub vars {
    my ($self, @args) = @_;

    $self->stash(
        base_url     => $self->config->get_key('web_ui:base_url'),
        cgi_base_url => $self->config->get_key('web_ui:cgi_base_url'),
        @args);
}

1;
