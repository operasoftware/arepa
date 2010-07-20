package Arepa::Web::Auth;

use strict;
use warnings;

use base 'Arepa::Web::Base';
use MojoX::Session;
use DBI;
use Digest::MD5;

my $session_db = "sessions.db";

sub login {
    my $self = shift;

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
        # my %users = %{YAML::LoadFile($config->get_key('web_ui:user_file'))};
        # if ($users{$user} eq Digest::MD5::md5_hex($password)) {
        if ($self->param('username') eq 'foo') {
            $session->create;
            $session->flush;
        }
    }
    else {
        $session->load;
    }

    if ($session->sid) {
        return 1;
    }
    $self->render('auth/login');
}

sub logout {
    my $self = shift;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$session_db");
    my $session = MojoX::Session->new(tx    => $self->tx,
                                      store => [dbi => {dbh => $dbh}]);
    $session->expire;
    $session->flush;

    $self->redirect_to($self->config->get_key('web_ui:cgi_base_url'));
}

1;
