package Arepa::Web;

use strict;
use warnings;

use base 'Mojolicious';

sub startup {
    my $self = shift;

    $self->secret("b1Tx3z.duN'tKn0Wbout4r3p4");

    # Routes
    my $r = $self->routes;
    my $auth = $r->bridge->to('auth#login');

    # Default route
    $auth->route('/')->to('dashboard#index')->name('home');
    $auth->route('/:controller/:action/:id')->name('generic_id');
    $auth->route('/:controller/:action')->name('generic');
}

1;
