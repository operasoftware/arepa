#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;
use File::Path;
use File::chmod;
use File::Find;

use Arepa::Config;

use constant AREPA_MASTER_USER => 'arepa-master';

my ($command, @args) = @ARGV;
if (scalar @ARGV == 0) {
    print STDERR "arepa-admin needs a command\n";
    print STDERR "Syntax: arepa-admin <command> <args> ...\n";
    exit 1;
}

if ($command eq 'createbuilder') {
    my ($builder_dir, $mirror, $distribution) = @args;
    if (scalar @args != 3) {
        print STDERR "createbuilder needs exactly three arguments\n";
        print STDERR "Syntax: arepa-admin createbuilder <schroot_dir> <debian_mirror> <distribution>\n";
        exit 1;
    }

    my $chroot_name = basename($builder_dir);
    my $debootstrap_cmd = "debootstrap --variant=buildd $distribution $builder_dir $mirror";
    my $r = system($debootstrap_cmd);
    if ($r != 0) {
        print STDERR "Error executing debootstrap: error code $r\n";
        print STDERR $debootstrap_cmd, "\n";
        exit 1;
    }

    # Create appropriate /etc/apt/sources.list
    open SOURCESLIST, ">$builder_dir/etc/apt/sources.list" or
        do {
            print STDERR "Couldn't write to /etc/apt/sources.list";
            exit 1;
        };
    print SOURCESLIST <<EOSOURCES;
deb $mirror $distribution main
deb http://localhost/arepa-repository $distribution main
deb-src http://localhost/arepa-repository $distribution main
EOSOURCES
    close SOURCESLIST;

    # Make sure certain directories exist and are writable by the 'sbuild'
    # group
    my ($login, $pass, $uid, $gid) = getpwnam(AREPA_MASTER_USER);
    foreach my $dir (qw(build var/lib/sbuild/srcdep-lock)) {
        my $full_path = "$builder_dir/$dir";
        unless (-d $full_path) {
            mkpath $full_path;
            find({ wanted => sub {
                        chmod("g+w", $File::Find::name);
                        chown $uid, $gid, $File::Find::name;
                   },
                   follow => 0 },
                 $full_path);
        }
    }

    Arepa::Builder::init_builder($builder_dir);
}
