package Arepa::Web::Public;

use strict;
use warnings;

use base 'Arepa::Web::Base';

sub rss {
    my $self = shift;

    $self->render_text("Public RSS yay!");
}

1;
