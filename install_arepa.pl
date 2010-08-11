#!/usr/bin/perl

use lib qw(lib);

use File::Path;
use File::Basename;
use File::chmod qw(symchmod);
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
                  $config->get_key("upload_queue:path"),
                  $config->get_key("dir:build_logs"),
                  $config->get_key("web_ui:gpg_homedir")) {
    print "Creating $path\n";
    mkpath($path);
    chown($uid, $gid, $path);
    symchmod("g+w", $path);
}

print "Creating package DB in $package_db_path\n";
my $package_db = Arepa::PackageDb->new($package_db_path);
chown($uid, $gid, $path);
symchmod("g+w", $path);
