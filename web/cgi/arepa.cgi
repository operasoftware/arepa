#!/usr/bin/perl

use strict;
use warnings;

use lib qw(/home/estebanm/src/apt-repo/repo-tools-web/);
use lib qw(/home/estebanm/src/apt-repo/Parse-Debian-Changes/trunk/lib);
use lib qw(/home/aptweb/perl/share/perl/5.8.8/);
use lib qw(/home/aptweb/www/repo-tools-web/);

use lib qw(/home/zoso/src/apt-web/arepa/lib);
use lib qw(/home/zoso/src/apt-web/Parse-Debian-PackageDesc/lib);

use Arepa::Web::App;

my $webapp = Arepa::Web::App->new;
$webapp->run;
