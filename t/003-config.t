use strict;
use warnings;

use Test::More tests => 4;
use Test::Deep;
use Arepa::Config;

use constant TEST_CONFIG_FILE => 't/config-test.yml';

my $c = Arepa::Config->new(TEST_CONFIG_FILE);
is($c->get_key('package_db'),
   "/home/zoso/src/apt-web/package.db",
   "Simple configuration keys should work");
is($c->get_key('upload_queue:path'),
   '/home/zoso/src/apt-web/incoming',
   "Nested configuration key should work");

cmp_deeply([ $c->get_builders ],
           [ qw(lenny64 lenny32 etch64 etch32) ],
           "Builder information should be correct");

my $expected_builder_info = {
    name                => 'lenny64',
    type                => 'sbuild',
    architecture        => 'amd64',
    architecture_all    => 'yes',
    distribution        => 'lenny-opera',
    other_distributions => [qw(lenny unstable)],
};
cmp_deeply({ $c->get_builder_config('lenny64') },
           $expected_builder_info,
           "Builder information for 'lenny64' should be correct");
