use strict;
use warnings;

use Test::More tests => 14;
use Test::Deep;
use File::Path;
use Arepa::BuilderFarm;

use constant TEST_CONFIG_FILE         => 't/config-test.yml';
use constant TEST_TARGETS_CONFIG_FILE => 't/config-compilation-targets-test.yml';
my $c = Arepa::Config->new(TEST_CONFIG_FILE);
unlink $c->get_key('package_db');
my $c2 = Arepa::Config->new(TEST_TARGETS_CONFIG_FILE);
unlink $c2->get_key('package_db');

my $bm = Arepa::BuilderFarm->new(TEST_CONFIG_FILE);
is($bm->builder_type_module('sbuild'),
   "Arepa::Builder::Sbuild",
   "Basic builder_type_module test should work");
is($bm->builder_type_module('sBuild'),
   "Arepa::Builder::Sbuild",
   "Strange capitalisation shouldn't confuse builder_type_module");
is($bm->builder_type_module('SBUILD'),
   "Arepa::Builder::Sbuild",
   "All uppercase shouldn't confuse builder_type_module");

cmp_deeply([ $bm->get_matching_builders('amd64', 'unstable') ],
           [qw(lenny64 etch64)],
           "Should correctly match builders for 'amd64'/'unstable'");

cmp_deeply([ $bm->get_matching_builders('any', 'lenny-opera') ],
           [qw(lenny64 lenny32)],
           "Should correctly match builders for 'any'/'lenny-opera'");

cmp_deeply([ $bm->get_matching_builders('any', 'lenny') ],
           [qw(lenny64 lenny32)],
           "Alias should be correctly recognised when match builders");

cmp_deeply([ $bm->get_matching_builders('amd64', 'lenny-opera') ],
           [qw(lenny64)],
           "Should correctly match builders for 'amd64'/'lenny-opera'");



my $bm2 = Arepa::BuilderFarm->new(TEST_TARGETS_CONFIG_FILE);

my %source_pkg1 = (name         => 'foo',
                   full_version => '1.0',
                   architecture => 'any',
                   distribution => 'unstable');
my $source_pkg1_id = $bm2->package_db->insert_source_package(%source_pkg1);
my $expected_targets1 = [[qw(amd64 lenny-opera)],
                         [qw(i386 lenny-opera)],
                         [qw(i386 etch-opera)]];
cmp_deeply([ $bm2->get_compilation_targets($source_pkg1_id) ],
           $expected_targets1,
           "The compilation targets for arch 'any' should be right");

my %source_pkg2 = (name         => 'bar',
                   full_version => '1.0',
                   architecture => 'all',
                   distribution => 'unstable');
my $source_pkg2_id = $bm2->package_db->insert_source_package(%source_pkg2);
my $expected_targets2 = [[qw(all lenny-opera)]];
cmp_deeply([ $bm2->get_compilation_targets($source_pkg2_id) ],
           $expected_targets2,
           "The compilation targets for arch 'all' should be right");

# Request the compilation of the first source package
is(scalar $bm2->package_db->get_compilation_queue,
   0,
   "The compilation queue should be empty");
$bm2->request_package_compilation($source_pkg1_id);
my @compilation_queue = $bm2->package_db->get_compilation_queue(status => 'pending');
is(scalar @compilation_queue,
   3,
   "The compilation queue should be empty");
$bm2->package_db->mark_compilation_started($compilation_queue[0]->{id},
                                           'etch32');
is(scalar $bm2->package_db->get_compilation_queue(status => 'pending'),
   2,
   "The compiling package shouldn't be in the pending queue anymore");




# Actually compile packages --------------------------------------------------
my $compilation_request_id = $compilation_queue[0]->{id};
my $tmp_dir = 't/tmp';
mkpath($tmp_dir);
$bm2->compile_package_from_queue('etch32',
                                 $compilation_request_id,
                                 $tmp_dir);
my @deb_files;
opendir D, $tmp_dir;
while (my $entry = readdir D) {
    push @deb_files, $entry if $entry =~ /\.deb$/;
}
closedir D;
ok(scalar @deb_files > 0,
   "There should be at least one .deb package in the result directory");
rmtree($tmp_dir);

# Check that the request is marked as 'compiled'
my @compiled_queue = $bm2->package_db->get_compilation_queue(status => 'compiled');
is($compiled_queue[0]->{id}, $compilation_request_id,
   "The first 'compiled' in the queue should be the one we just compiled");
