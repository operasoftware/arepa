# $Id$
# $Source$
# $Author$
# $HeadURL$
# $Revision$
# $Date$
package Arepa::Web::App;

use strict;
use warnings;
our $VERSION = 0.10;
use 5.00800;

use Carp    qw(carp croak); # NEVER USE warn OR die !
use English qw(-no_match_vars);
use File::Basename;
use File::Copy;

use base qw(CGI::Application);
use CGI::Application::Plugin::TT;
use CGI::Application::Plugin::Authentication;
use CGI::Application::Plugin::Session;
use YAML;
use Data::Dumper;

use Parse::Debian::PackageDesc;
use Arepa::Config;
use Arepa::Repository;

my @conffiles = qw(/home/estebanm/src/apt-repo/repo-tools-web/config.yml \
                   /home/aptweb/www/repo-tools-web/config.yml \
                   /home/zoso/src/apt-web/repo-tools-web/config.yml);
our $config      = undef;
our $config_path = undef;
foreach my $conffile (@conffiles) {
    if (-r $conffile) {
        $config_path = $conffile;
        $config = Arepa::Config->new($config_path);
        last ;
    }
}

# This is a sub for CGI::Application authentication module
sub validate_username_password {
    my ($user, $password) = @_;
    my %users = %{YAML::LoadFile($config->get_key('web_ui:user_file'))};
    return ($users{$user} eq $password);
}

sub setup {
    my ($self) = @_;

    $self->authen->config(
        DRIVER => [ 'Generic', \&validate_username_password ],
        LOGOUT_RUNMODE => 'logout',
    );
    $self->session_config(CGI_SESSION_OPTIONS => ["driver:File",
                                                  $self->query,
                                                  {Directory=>'/tmp'}],
                          DEFAULT_EXPIRY => '+1w',
                          COOKIE_PARAMS  => {-expires => '+24h', -path => '/'},
                          SEND_COOKIE    => 1);
    $self->authen->protected_runmodes(':all');
    $self->authen->protected_runmodes('logout');
    $self->start_mode('list');
    $self->mode_param('rm');
    $self->run_modes(
            'list'        => 'list_pending',
            'approve'     => 'approve',
            'approve_all' => 'approve_all',
            'logout'      => 'logout',
    );
    $self->tt_include_path($config->get_key('web_ui:template_dir'));

    $self->{error_list} = [];
}

sub show_view {
    my ($self, $template, $stash) = @_;

    $self->tt_process($template, { $self->base_stash,
                                   %$stash });
}

sub base_stash {
    my ($self) = @_;
    (base_url => $config->get_key('web_ui:base_url'));
}

sub add_error {
    my ($self, $error) = @_;
    push @{$self->{error_list}}, $error;
}

sub error_list {
    my ($self) = @_;
    @{$self->{error_list}};
}

sub last_cmd_output {
    my ($self) = @_;
    $self->{last_cmd_output};
}

sub list_pending {
    my ($self) = @_;

    opendir D, $config->get_key('upload_queue:path');
    my @packages = grep /\.changes$/, readdir D;
    closedir D;

    my (@readable_packages, @unreadable_packages);
    my $gpg_dir = $config->get_key('web_ui:gpg_homedir');
    foreach my $package (@packages) {
        my $package_path = $config->get_key('upload_queue:path')."/".$package;
        my $obj = undef;
        eval {
            $obj = Parse::Debian::PackageDesc->new($package_path,
                                                   gpg_homedir => $gpg_dir);
        };
        if ($obj) {
            push @readable_packages, $obj;
        }
        else {
            push @unreadable_packages, $package;
        }
    }
    $self->show_view('index.tmpl',
                     {packages            => \@readable_packages,
                      unreadable_packages => \@unreadable_packages,
                      rm                  => join(", ", $self->query->param('rm'))});
}

sub approve {
    my ($self) = @_;

    $self->approve_package($self->query->param('package'));
    if ($self->error_list) {
        my $r = $self->show_view('error.tmpl',
                                 {errors => [$self->error_list]});
        use Data::Dumper;
        return $r;
    }
    else {
        $self->_redirect("arepa.cgi");
    }
}

sub approve_all {
    my ($self) = @_;

    foreach my $package ($self->query->param('packages')) {
        $self->approve_package($package);
    }
    if ($self->error_list) {
        my $r = $self->show_view('error.tmpl',
                                 {errors => [$self->error_list]});
        return $r;
    }
    else {
        $self->_redirect("arepa.cgi");
    }
}


sub approve_package {
    my ($self, $changes_file_path) = @_;

    # Only get the file basename, and search for it in the incoming directory
    my $path = $config->get_key('upload_queue:path')."/".basename($changes_file_path);
    my $changes_file = Parse::Debian::PackageDesc->new($path);
    my $distribution = $changes_file->distribution;

    # Add the source package to the repo
    my $package_revision_base_name = $changes_file->source."_".
                                        $changes_file->version;
    my $source_file_path = $package_revision_base_name.".dsc";
    my $repository = Arepa::Repository->new($config_path);
    if (!$repository->insert_source_package($config->get_key('upload_queue:path')."/".
                                                $source_file_path,
                                            $distribution)) {
        $self->add_error("Couldn't approve source package $source_file_path. ".
                            "Command output was: ".
                            $repository->last_cmd_output);
    }

    if ($self->error_list) {
        return 0;
    }
    else {
        # Remove all files from the pending queue
        # Files referenced by the changes file
        foreach my $file ($changes_file->files) {
            my $file_path = $config->get_key('upload_queue:path')."/".$file;
            if (-e $file_path && ! unlink($file_path)) {
                $self->add_error("Can't delete $file_path");
            }
        }
        # Changes file itself
        if (! unlink($path)) {
            $self->add_error("Can't delete $path");
        }

        if ($self->error_list) {
            return 0;
        }
    }

    return 1;
}


sub logout {
    my ($self) = @_;

    $self->authen->logout;
    $self->_redirect("arepa.cgi");
}

sub _redirect {
    my ($self, $url) = @_;
    $self->header_type('redirect');
    $self->header_props(-url => $url);
}

1;

__END__

=begin wikidoc

= NAME

PackageApprovalApp - CGI::Application app for Debian package approval


= VERSION

This document describes My Opera version %%VERSION%%

= SYNOPSIS

    use PackageApprovalApp;
    PackageApprovalApp->run;

= DESCRIPTION

Write the modules description here.

= DIAGNOSTICS

No error messages.

= CONFIGURATION AND ENVIRONMENT

This module requires no configuration file or environment variables.

= DEPENDENCIES

* {CGI::Application}
* {CGI::Application::Plugin::Authentication}
* {CGI::Application::Plugin::TT}

= INCOMPATIBILITIES

None known.

= BUGS AND LIMITATIONS

No bugs have been reported.

= SEE ALSO

== Parse::Debian::Packages

== CGI::Application

= AUTHOR

Esteban Manchado Velázquez <estebanm@opera.com>.

= LICENSE AND COPYRIGHT

= DISCLAIMER OF WARRANTY


=end wikidoc

=for stopwords expandtab shiftround

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
# End:
# vim: expandtab tabstop=4 shiftwidth=4 shiftround
