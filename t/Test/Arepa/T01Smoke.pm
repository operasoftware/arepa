#!/usr/bin/perl

package Test::Arepa::T01Smoke;

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Test::Arepa;

use base qw(Test::Arepa);

sub setup : Test(setup => 7) {
    my ($self, @args) = @_;

    $self->config_path('t/webui/conf/default/config.yml');
    $self->SUPER::setup(@_);

    $self->login_ok("testuser", "testuser's password");
}

sub test_login : Test(1) {
    my $self = shift;
    ok(1);
}

1;
