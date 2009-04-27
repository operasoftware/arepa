#!/usr/bin/perl

use strict;
use warnings;
use Arepa::PackageDb;
use Arepa::Config;

# Arepa::PackageDb->new('package.db');

my $config = Arepa::Config->new('config.yml');
use Data::Dumper;
print Dumper($config->get_builder_config('lenny32'));
print Dumper($config->get_builder_config_key('lenny64', 'archs'));
print $config->get_builder_config_key('lenny32', 'distribution'), "\n";
