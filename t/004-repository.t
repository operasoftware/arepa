use strict;
use warnings;

use Test::More;

if (exists $ENV{REPREPRO4PATH} and -x $ENV{REPREPRO4PATH}) {
    plan tests => 23;
}
else {
    plan skip_all => "Please specify the path to reprepro 4 in \$REPREPRO4PATH";
}

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

ok($r->config_key_exists('package_db'),
   "Existing config keys should be recognised");
ok(!$r->config_key_exists('i_dont_exist'),
   "Non-existing config keys should NOT be recognised");

my $expected_distributions = [{ codename      => 'lenny-opera',
                                components    => 'main',
                                architectures => 'source i386 amd64',
                                suite         => 'Lenny',
                                version       => '5.0'},
                              { codename      => 'etch-opera',
                                components    => 'main',
                                architectures => 'i386',
                                origin        => 'Opera'}];
cmp_deeply([ $r->get_distributions ],
           $expected_distributions,
           "Distribution information should be correct");
cmp_deeply([ $r->get_architectures ],
           [ qw(source i386 amd64) ],
           "The architectures should be complete and not duplicated");


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


# Insert a new source package into the repository, with comments -------------
my $comments = "Now with comments";
ok($r->insert_source_package('t/upload_queue/foobar_1.0-1.dsc', 'lenny-opera',
                             comments => $comments),
   "Inserting a new source package (w/ comments) should succeed");
my $id_w_comments = $r->{package_db}->get_source_package_id('foobar', '1.0-1');
ok($id_w_comments,
   "After inserting the source package, it should be in the package db");
my %source_pkg_w_comments =
            $r->{package_db}->get_source_package_by_id($id_w_comments);
is($source_pkg_w_comments{comments}, $comments,
   "The source package should keep its comments, if any");

my $fh2 = new IO::Zlib;
my $package_line_found2    = 0;
my $correct_version_found2 = 0;
if ($fh2->open("t/repo-test/dists/lenny-opera/main/source/Sources.gz", "rb")) {
    while (my $line = <$fh2>) {
        chomp $line;
        if ($line eq 'Package: foobar') {
            $package_line_found2 = 1;
        }
        elsif ($line eq 'Version: 1.0-1') {
            $correct_version_found2 = 1;
        }
    }
    $fh2->close;
}
ok($package_line_found2,    "Should find the package in Sources.gz");
ok($correct_version_found2, "Should find the correct version in Sources.gz");


# Package list ---------------------------------------------------------------
cmp_deeply({ $r->package_list },
          {
              foobar => { "lenny-opera/main" => { "1.0-1"  => ['source'] } },
              dhelp  => { "lenny-opera/main" => { "0.6.15" => set(qw(i386
                                                                     amd64
                                                                     source)),
                                                } },
          },
          "The final package list should be correct");

# Insert mixed versions of a new package
$r->insert_source_package('t/upload_queue/qux_1.0-1.dsc', 'lenny-opera');
$r->insert_binary_package('t/upload_queue/qux_1.0-1_i386.deb',  'lenny-opera');
$r->insert_binary_package('t/upload_queue/qux_1.0-1_amd64.deb', 'lenny-opera');
$r->insert_binary_package('t/upload_queue/qux_1.0-2_i386.deb',  'lenny-opera');

# Now check the package list
cmp_deeply({ $r->package_list },
           {
               foobar => { "lenny-opera/main" => { "1.0-1" => ['source'] } },
               qux    => { "lenny-opera/main" => { "1.0-1" => set(qw(amd64
                                                                     source)),
                                                   "1.0-2" => ['i386'],
                                                 } },
               dhelp  => { "lenny-opera/main" => { "0.6.15" => set(qw(i386
                                                                      amd64
                                                                      source)),
                                                 } },
           },
           "The final package list should be correct");


# Insert a source package with non-canonical distribution --------------------
ok(! $r->insert_source_package('t/upload_queue/experimental-package_1.0.dsc',
                               'experimental'),
   "Inserting source package w/ non-canonical distro should fail");

ok($r->insert_source_package('t/upload_queue/experimental-package_1.0.dsc',
                             'experimental',
                             canonical_distro => 'lenny-opera'),
   "Inserting non-canonical distro source package w/ canonical distro hint");
# Ugly way of checking that the source package is correctly inserted
my $id = $r->{package_db}->get_source_package_id('experimental-package',
                                                 '1.0');
my %source_package_attrs = $r->{package_db}->get_source_package_by_id($id);
is($source_package_attrs{distribution}, 'experimental',
   "When inserting a non-canonical distro package, the distro is correct");
