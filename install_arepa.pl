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

my $arepa_user  = "arepa-master";
my $arepa_group = "arepa";
my $web_user    = "www-data";
my $web_group   = "www-data";

my $config = Arepa::Config->new("/etc/arepa/config.yml");

my $uid = getgrnam($arepa_user);
if (!defined $uid) {
    print STDERR "ERROR: User '$arepa_user' doesn't exist\n";
    exit 1;
}
my $gid = getgrnam($arepa_group);
if (!defined $gid) {
    print STDERR "ERROR: Group '$arepa_group' doesn't exist\n";
    exit 1;
}
my $web_uid = getgrnam($web_user);
if (!defined $web_uid) {
    print STDERR "ERROR: User '$web_user' doesn't exist\n";
    exit 1;
}
my $web_gid = getgrnam($web_group);
if (!defined $web_gid) {
    print STDERR "ERROR: Group '$web_group' doesn't exist\n";
    exit 1;
}

my $package_db_path = $config->get_key("package_db");
foreach my $path (dirname($package_db_path),
                  $config->get_key("repository:path"),
                  File::Spec->catfile($config->get_key("repository:path"),
                                      "conf"),
                  $config->get_key("upload_queue:path"),
                  $config->get_key("dir:build_logs")) {
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

my $gpg_dir = $config->get_key("web_ui:gpg_homedir");
print "Creating GPG directory in $gpg_dir\n";
mkpath($gpg_dir);
chown($web_uid, $web_gid, $gpg_dir);
chmod(0770, $gpg_dir);

my $gpg_options = File::Spec->catfile($config->get_key("web_ui:gpg_homedir"),
                                      "options");
if (! -f $gpg_options) {
    print "Creating options file $gpg_options\n";
    my $keyrings_dir =
        File::Spec->catfile(dirname($config->get_key("web_ui:gpg_homedir")),
                            "keyrings");
    mkpath($keyrings_dir);
    chown($uid, $gid, $keyrings_dir);
    symchmod("g+w", $keyrings_dir);

    open F, ">$gpg_options";
    print F "keyring $keyrings_dir/uploaders.gpg\n";
    close F;
    chown($uid, $gid, $gpg_options);
    symchmod("g+w", $gpg_options);
}
