package Arepa::Web;

use strict;
use warnings;

use base 'Mojolicious';

sub startup {
    my $self = shift;

    # Routes
    my $r = $self->routes;
    my $auth = $r->bridge->to('auth#login');

    # Default route
    $auth->route('/')->to('dashboard#index');
    $auth->route('/:controller/:action')->name('generic');
}

1;
