#!/usr/bin/perl

package Test::Arepa::T01Smoke;

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Test::Arepa;
use File::Copy;

use base qw(Test::Arepa);

sub setup : Test(setup => 7) {
    my ($self, @args) = @_;

    $self->config_path('t/webui/conf/default/config.yml');
    $self->SUPER::setup(@_);

    $self->login_ok("testuser", "testuser's password");
}

sub test_should_see_builders : Test(1) {
    my $self = shift;
    $self->t->content_like(qr/test-builder/);
}

sub test_incoming_package_list : Test(3) {
    my $self = shift;

    is($self->incoming_packages, 0,
       "There should not be any incoming packages to start with");

    # Copy one package to the upload queue, see what happens
    foreach my $file (glob('t/webui/fixtures/foobar_1.0*')) {
        copy($file,
             $self->config->get_key('upload_queue:path'));
    }

    $self->t->get_ok('/');
    is_deeply([ $self->incoming_packages ], [qw(foobar_1.0-1)],
              "Package 'foobar' should be in the upload queue");
}

1;
