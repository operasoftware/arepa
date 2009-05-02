use strict;
use warnings;

use Test::More tests => 4;
use Test::Deep;
use Arepa::Repository;

use constant TEST_CONFIG_FILE => 't/config-test.yml';

my $r = Arepa::Repository->new(TEST_CONFIG_FILE);
is($r->get_config_key('package_db'),
   "t/test-package.db",
   "Simple configuration keys should work");
is($r->get_config_key('upload_queue:path'),
   '/home/zoso/src/apt-web/incoming',
   "Nested configuration key should work");
unlink $r->get_config_key('package_db');

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
