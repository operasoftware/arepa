package Arepa::Web::Public;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# This action will render a template
sub rss {
    my $self = shift;

    $self->render_text("Public RSS yay!");
}

1;
