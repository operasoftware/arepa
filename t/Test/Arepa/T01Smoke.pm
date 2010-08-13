#!/usr/bin/perl

package Test::Arepa::T01Smoke;

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Test::Arepa;

use base qw(Test::Arepa);

sub setup : Test(setup) {
    my ($self, @args) = @_;

    $self->config_path('t/webui/conf/default/config.yml');
    $self->SUPER::setup(@_);
}

sub test_login : Test(7) {
    my $self = shift;

    my $t = Test::Mojo->new(app => 'Arepa::Web');
    $t->get_ok('/')->
        status_is(200)->
        content_like(qr/arepa_test_logged_out/);
    $t->post_form_ok('/' => {username => "testuser",
                             password => "testuser's password"});
    $t->get_ok('/')->
        status_is(200);
    unlike($t->tx->res->body, qr/arepa_test_logged_out/);
}

1;
