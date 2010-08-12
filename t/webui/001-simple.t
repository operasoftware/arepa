#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Mojo;
use Cwd;

$ENV{AREPA_CONFIG} = 't/webui/conf/default/config.yml';
$ENV{MOJO_HOME} = cwd;

system("echo 'CREATE TABLE session (sid VARCHAR(40) PRIMARY KEY, data TEXT, expires INTEGER UNSIGNED NOT NULL, UNIQUE(sid));' | sqlite3 t/webui/tmp/sessions.db");

my $t = Test::Mojo->new(app => 'Arepa::Web');
$t->get_ok('/')->
    status_is(200)->
    content_like(qr/arepa_test_logged_out/);
$t->post_form_ok('/' => {username => "testuser",
                         password => "testuser's password"});
$t->get_ok('/')->
    status_is(200);
unlike($t->tx->res->body, qr/arepa_test_logged_out/);
