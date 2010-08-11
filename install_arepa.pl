#!/usr/bin/perl

use strict;
use warnings;

use lib qw(lib);

use File::Path;
use File::Basename;
use File::chmod qw(symchmod);
use File::Spec;
use Arepa::Config;
use Arepa::PackageDb;

my $config = Arepa::Config->new("/etc/arepa/config.yml");

my $uid = getgrnam("arepa-master");
if (!defined $uid) {
    print STDERR "ERROR: User 'arepa-master' doesn't exist\n";
    exit 1;
}
my $gid = getgrnam("arepa");
if (!defined $gid) {
    print STDERR "ERROR: Group 'arepa' doesn't exist\n";
    exit 1;
}

my $package_db_path = $config->get_key("package_db");
foreach my $path (dirname($package_db_path),
                  $config->get_key("repository:path"),
                  File::Spec->catfile($config->get_key("repository:path"),
                                      "conf"),
                  $config->get_key("upload_queue:path"),
                  $config->get_key("dir:build_logs"),
                  $config->get_key("web_ui:gpg_homedir")) {
    print "Creating directory $path\n";
    mkpath($path);
    chown($uid, $gid, $path);
    symchmod("g+w", $path);
}

my $builder_dir = "/etc/arepa/builders";
print "Creating builder configuration directory $builder_dir\n";
mkpath($builder_dir);
chown($uid, $gid, $builder_dir);
symchmod("g+w", $builder_dir);

print "Creating package DB in $package_db_path\n";
my $package_db = Arepa::PackageDb->new($package_db_path);
chown($uid, $gid, $package_db_path);
symchmod("g+w", $package_db_path);

my $repo_dists_conf = File::Spec->catfile($config->get_key("repository:path"),
                                          "conf",
                                          "distributions");
print "Creating repo configuration file in $repo_dists_conf\n";
open F, ">>$repo_dists_conf";
close F;
chown($uid, $gid, $repo_dists_conf);
symchmod("g+w", $repo_dists_conf);
