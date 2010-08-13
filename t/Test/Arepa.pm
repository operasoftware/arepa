package Test::Arepa;

use strict;
use warnings;

use Test::Class;
use Test::More;
use Cwd;
use File::Path;
use HTML::TreeBuilder;

use Arepa::Config;

use base qw(Test::Class);

sub config_path {
    my $self = shift;

    if (@_) {
        $self->{config_path} = shift;
    }
    return $self->{config_path};
}

sub config { $_[0]->{config}; }

sub t {
    my $self = shift;
    $self->{t} ||= Test::Mojo->new(app => 'Arepa::Web');
    return $self->{t};
}

sub setup : Test(setup) {
    my $self = shift;

    my $config_path = $self->{config_path} ||
                        't/webui/conf/default/config.yml';
    $self->{config} = Arepa::Config->new($config_path);

    # Make the configuration path available to the application
    $ENV{AREPA_CONFIG} = $config_path;
    # Needed so the application finds all the files
    $ENV{MOJO_HOME}    = cwd;

    # ALWAYS recreate the temporary directory
    rmtree('t/webui/tmp');
    mkpath('t/webui/tmp');

    # Prepare the session DB
    my $session_db_path = $self->{config}->get_key('web_ui:session_db');
    unlink $session_db_path;
    system("echo 'CREATE TABLE session (sid VARCHAR(40) PRIMARY KEY, " .
                                       "data TEXT, " .
                                       "expires INTEGER UNSIGNED NOT NULL, " .
                                       "UNIQUE(sid));' | " .
                                       "    sqlite3 '$session_db_path'");
    
    # Make sure the upload queue exists
    mkpath($self->{config}->get_key('upload_queue:path'));
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

sub incoming_packages {
    my ($self) = @_;

    my $tree = HTML::TreeBuilder->new;
    $tree->parse_content($self->t->tx->res->body);

    # Get the package names
    my @pkg_names = map {
                         $_->as_text;
                    }
                    $tree->look_down(sub {
                            grep { $_ eq 'incoming-package-name' }
                                 split(' ',
                                       ($_[0]->attr('class') || "")) });

    my @pkg_versions = map {
                            $_->as_text;
                       }
                       $tree->look_down(sub {
                               grep { $_ eq 'incoming-package-version' }
                                    split(' ',
                                          ($_[0]->attr('class') || "")) });

    my @r = ();
    for (my $i = 0; $i <= $#pkg_names; ++$i) {
        push @r, $pkg_names[$i] . "_" . $pkg_versions[$i];
    }
    return @r;
}

1;
