package Arepa::Web::Auth;

use strict;
use warnings;

use base 'Arepa::Web::Base';
use DBI;
use Digest::MD5;
use YAML;
use MojoX::Session;

# Let session cookies live one week
use constant TTL_SESSION_COOKIE => 60 * 60 * 24 * 7;

sub _auth {
    my ($self, $username, $password) = @_;

    my %users = %{YAML::LoadFile($self->config->get_key('web_ui:user_file'))};
    return ($users{$username} eq Digest::MD5::md5_hex($password));
}

sub login {
    my $self = shift;

    my $session_db = $self->config->get_key('web_ui:session_db');
    my $dbh = DBI->connect("dbi:SQLite:dbname=$session_db");
    my $session = MojoX::Session->new(tx            => $self->tx,
                                      store         => [dbi => {dbh => $dbh}],
                                      expires_delta => TTL_SESSION_COOKIE);

    # Don't check anything for public URLs
    my $url_parts = $self->tx->req->url->path->parts;
    if (scalar @$url_parts && $url_parts->[0] eq 'public') {
        $session->load;
        return 1;
    }

    # External authentication
    my $auth_type_key = 'web_ui:authentication:type';
    if ($self->config->key_exists($auth_type_key) &&
            $self->config->get_key($auth_type_key) eq 'external') {
        if ($ENV{REMOTE_USER}) {
            $session->load;
            if (! $session->sid || $session->is_expired) {
                $session->create;
                $session->flush;
            }
        }
        else {
            $self->vars("error" => "Authentication error: your webserver is " .
                                       "not passing the REMOTE_USER " .
                                       "environment variable to the " .
                                       "application");
        }
    }
    else {
        if (defined $self->param('username') &&
                defined $self->param('password')) {
            if ($self->_auth($self->param('username'),
                             $self->param('password'))) {
                $session->create;
                $session->flush;
            } else {
                $self->vars("error" => "Invalid username or password");
            }
        } else {
            $session->load;
        }
    }

    if ($session->sid) {
        return 1;
    }
    $self->vars();
    $self->render('auth/login', layout => 'default');
    return 0;
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
