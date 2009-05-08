use strict;
use warnings;

use Test::More tests => 11;
use Test::Deep;
use File::Path;
use IO::Zlib;

use Arepa::Repository;

use constant TEST_CONFIG_FILE => 't/config-test.yml';

# Always start fresh
my $test_repo_path = 't/repo-test';
my $test_db_path   = 't/test-package.db';
foreach my $subdir (qw(db dists pool)) {
    rmtree "$test_repo_path/$subdir";
}
unlink $test_db_path;

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


# Insert a new source package into the repository ----------------------------
ok($r->insert_source_package('t/upload_queue/dhelp_0.6.15.dsc', 'lenny-opera'),
   "Inserting a new source package should succeed");
ok($r->{package_db}->get_source_package_id('dhelp', '0.6.15'),
   "After inserting the source package, it should be in the package db");

my $fh = new IO::Zlib;
my $package_line_found    = 0;
my $correct_version_found = 0;
if ($fh->open("t/repo-test/dists/lenny-opera/main/source/Sources.gz", "rb")) {
    while (my $line = <$fh>) {
        chomp $line;
        if ($line eq 'Package: dhelp') {
            $package_line_found = 1;
        }
        elsif ($line eq 'Version: 0.6.15') {
            $correct_version_found = 1;
        }
    }
    $fh->close;
}
ok($package_line_found,    "Should find the package in Sources.gz");
ok($correct_version_found, "Should find the correct version in Sources.gz");



# Insert a new binary package into the repository ----------------------------
ok($r->insert_binary_package('t/upload_queue/dhelp_0.6.15_all.deb',
                             'lenny-opera'),
   "Inserting a new binary package should succeed");

my $binary_package_found = 0;
my $binary_version_found = 0;
if (open F, 't/repo-test/dists/lenny-opera/main/binary-i386/Packages') {
    while (my $line = <F>) {
        chomp $line;
        if ($line eq 'Package: dhelp') {
            $binary_package_found = 1;
        }
        elsif ($line eq 'Version: 0.6.15') {
            $binary_version_found = 1;
        }
    }
    close F;
}
ok($binary_package_found,
   "After adding a binary package, it should be in the package list");
ok($binary_version_found,
   "After adding a binary package, the package version should be correct");
