package Arepa::UI::Text;

sub print_info {
    my ($self, $msg) = @_;

    my $len = length $msg;
    print $msg, " ", "=" x (78 - 1 - $len), "\n";
}

1;
