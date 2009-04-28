use strict;
use warnings;

use Test::More tests => 10;
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



my $r_targets = Arepa::Repository->new('t/config-compilation-targets-test.yml');

my %source_pkg1 = (name         => 'foo',
                   full_version => '1.0',
                   architecture => 'any',
                   distribution => 'unstable');
my $source_pkg1_id = $r_targets->insert_source_package(%source_pkg1);
my $expected_targets1 = [[qw(amd64 lenny-opera)],
                         [qw(i386 lenny-opera)],
                         [qw(i386 etch-opera)]];
cmp_deeply([ $r_targets->get_compilation_targets($source_pkg1_id) ],
           $expected_targets1,
           "The compilation targets for arch 'any' should be right");

my %source_pkg2 = (name         => 'bar',
                   full_version => '1.0',
                   architecture => 'all',
                   distribution => 'unstable');
my $source_pkg2_id = $r_targets->insert_source_package(%source_pkg2);
my $expected_targets2 = [[qw(all lenny-opera)]];
cmp_deeply([ $r_targets->get_compilation_targets($source_pkg2_id) ],
           $expected_targets2,
           "The compilation targets for arch 'all' should be right");
