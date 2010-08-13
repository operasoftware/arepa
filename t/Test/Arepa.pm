package Test::Arepa;

use strict;
use warnings;

use Test::Class;
use Test::More;
use Arepa::Config;
use Cwd;

use base qw(Test::Class);

sub config_path {
    my $self = shift;

    if (@_) {
        $self->{config_path} = shift;
    }
    return $self->{config_path};
}

sub t {
    my $self = shift;
    $self->{t} ||= Test::Mojo->new(app => 'Arepa::Web');
    return $self->{t};
}

sub setup : Test(setup) {
    my $self = shift;

    my $config_path = $self->{config_path} ||
                        't/webui/conf/default/config.yml';
    my $config = Arepa::Config->new($config_path);

    # Make the configuration path available to the application
    $ENV{AREPA_CONFIG} = $config_path;
    # Needed so the application finds all the files
    $ENV{MOJO_HOME}    = cwd;

    # Prepare the session DB
    my $session_db_path = $config->get_key('web_ui:session_db');
    unlink $session_db_path;
    system("echo 'CREATE TABLE session (sid VARCHAR(40) PRIMARY KEY, " .
                                       "data TEXT, " .
                                       "expires INTEGER UNSIGNED NOT NULL, " .
                                       "UNIQUE(sid));' | " .
                                       "    sqlite3 '$session_db_path'");
    
}

sub login_ok {
    my ($self, $username, $password) = @_;

    $self->t->get_ok('/')->
              status_is(200)->
              content_like(qr/arepa_test_logged_out/);
    $self->t->post_form_ok('/' => {username => "testuser",
                                   password => "testuser's password"});
    $self->t->get_ok('/')->
              status_is(200);
    unlike($self->t->tx->res->body, qr/arepa_test_logged_out/);
}

1;
