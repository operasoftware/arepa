package Arepa::Web;

use strict;
use warnings;

use base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Routes
    my $r = $self->routes;
    my $auth = $r->bridge->to('auth#login');

    # Default route
    $auth->route('/')->to('dashboard#index');
    $auth->route('/:controller/:action')->to('example#welcome');
}

1;
