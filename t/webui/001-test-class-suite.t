#!/usr/bin/perl

use lib qw(t);
use Test::Arepa::T01Smoke;
use Test::More;

if (exists $ENV{REPREPRO4PATH} and -x $ENV{REPREPRO4PATH}) {
    Test::Class->runtests;
}
else {
    plan skip_all => "Please specify the path to reprepro 4 in \$REPREPRO4PATH";
}
