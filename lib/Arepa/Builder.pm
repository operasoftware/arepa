package Arepa::Builder;

sub init_builder {
    my ($builder_dir) = @_;

    # Bind some important files to the 'host'
    foreach my $etc_file (qw(resolv.conf passwd shadow group gshadow)) {
        my $full_path = "$builder_dir/etc/$etc_file";
        unless (-e $full_path) {
            my $atime = time;
            utime $atime, $atime, $full_path;
        }
        system(qq(mount -oro,bind "/etc/$etc_file" "$full_path"));
    }
}

1;
