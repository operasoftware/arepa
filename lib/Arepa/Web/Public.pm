package Arepa::Web::Public;

use strict;
use warnings;

use base 'Mojolicious::Controller';

sub rss {
    my $self = shift;

    $self->render_text("Public RSS yay!");
}

1;
