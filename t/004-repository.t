use strict;
use warnings;

use Test::More tests => 8;
use Test::Deep;
use Arepa::Repository;

use constant TEST_CONFIG_FILE => 't/config-test.yml';

my $r = Arepa::Repository->new(TEST_CONFIG_FILE);
is($r->get_config_key('package_db'),
   "/home/zoso/src/apt-web/package.db",
   "Simple configuration keys should work");
is($r->get_config_key('upload_queue:path'),
   '/home/zoso/src/apt-web/incoming',
   "Nested configuration key should work");

my $expected_repositories = [{ codename      => 'lenny-opera',
                               components    => 'main',
                               architectures => 'source i386 amd64',
                               suite         => 'Lenny',
                               version       => '5.0'},
                             { codename      => 'etch-opera',
                               components    => 'main',
                               architectures => 'i386',
                               origin        => 'Opera'}];
cmp_deeply([ $r->get_repositories ],
           $expected_repositories,
           "Repository information should be correct");
cmp_deeply([ $r->get_repository_architectures ],
           [ qw(source i386 amd64) ],
           "The repository architectures should be complete and not duplicated");

cmp_deeply([ $r->get_matching_builders('amd64', 'unstable') ],
           [qw(lenny64 etch64)],
           "Should correctly match builders for 'amd64'/'unstable'");

cmp_deeply([ $r->get_matching_builders('any', 'lenny-opera') ],
           [qw(lenny64 lenny32)],
           "Should correctly match builders for 'any'/'lenny-opera'");

cmp_deeply([ $r->get_matching_builders('any', 'lenny') ],
           [qw(lenny64 lenny32)],
           "Alias should be correctly recognised when match builders");

cmp_deeply([ $r->get_matching_builders('amd64', 'lenny-opera') ],
           [qw(lenny64)],
           "Should correctly match builders for 'amd64'/'lenny-opera'");
