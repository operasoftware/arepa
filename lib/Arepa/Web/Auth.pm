package Arepa::Web::Auth;

use strict;
use warnings;

use base 'Arepa::Web::Base';
use DBI;
use Digest::MD5;
use YAML;
use MojoX::Session;

sub _auth {
    my ($self, $username, $password) = @_;

    my %users = %{YAML::LoadFile($self->config->get_key('web_ui:user_file'))};
    return ($users{$username} eq Digest::MD5::md5_hex($password));
}

sub login {
    my $self = shift;

    my $session_db = $self->config->get_key('web_ui:session_db');
    my $dbh = DBI->connect("dbi:SQLite:dbname=$session_db");
    my $session = MojoX::Session->new(tx    => $self->tx,
                                      store => [dbi => {dbh => $dbh}]);

    # Don't check anything for public URLs
    my $url_parts = $self->tx->req->url->path->parts;
    if (scalar @$url_parts && $url_parts->[0] eq 'public') {
        $session->load;
        return 1;
    }


    # Logging the user if it's giving credentials
    if (defined $self->param('username') &&
            defined $self->param('password')) {
        if ($self->_auth($self->param('username'),
                         $self->param('password'))) {
            $session->create;
            $session->flush;
        }
        else {
            $self->vars("error" => "Invalid username or password");
        }
    }
    else {
        $session->load;
    }

    if ($session->sid) {
        return 1;
    }
    $self->vars();
    $self->render('auth/login', layout => 'default');
}

sub logout {
    my $self = shift;

    my $session_db = $self->config->get_key('web_ui:session_db');
    my $dbh = DBI->connect("dbi:SQLite:dbname=$session_db");
    my $session = MojoX::Session->new(tx    => $self->tx,
                                      store => [dbi => {dbh => $dbh}]);
    $session->expire;
    $session->flush;

    $self->redirect_to('home');
}

1;
