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
use Arepa::BuilderFarm;

my @conffiles = qw(/etc/arepa/config.yml);
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
    $self->start_mode('home');
    $self->mode_param('rm');
    $self->run_modes(
            'home'        => 'home',
            'approve'     => 'approve',
            'approve_all' => 'approve_all',
            'build_log'   => 'show_build_log',
            'requeue'     => 'requeue',
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
    (base_url     => $config->get_key('web_ui:base_url'),
     cgi_base_url => $config->get_key('web_ui:cgi_base_url'));
}

sub add_error {
    my ($self, $error, $output) = @_;
    push @{$self->{error_list}}, {error  => $error,
                                  output => $output};
}

sub error_list {
    my ($self) = @_;
    @{$self->{error_list}};
}

sub last_cmd_output {
    my ($self) = @_;
    $self->{last_cmd_output};
}

sub home {
    my ($self) = @_;

    my @packages = ();
    if (opendir D, $config->get_key('upload_queue:path')) {
        @packages = grep /\.changes$/, readdir D;
        closedir D;
    }

    # Packages pending approval ----------------------------------------------
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

    # Compilation queue ------------------------------------------------------
    my $packagedb = Arepa::PackageDb->new($config->get_key('package_db'));
    my @compilation_queue = $packagedb->
                                get_compilation_queue(status => 'pending',
                                                      limit  => 10);
    my @pending_compilations = ();
    foreach my $comp (@compilation_queue) {
        my %source_pkg_attrs =
            $packagedb->get_source_package_by_id($comp->{source_package_id});
        push @pending_compilations, {
            %$comp,
            package => { %source_pkg_attrs },
        };
    }

    # Builder status ---------------------------------------------------------
    # Get the builder information and find out which package is being compiled
    # by each builder, if any
    my @builder_list = ();
    my @compiling_packages = $packagedb->
                                get_compilation_queue(status => 'compiling',
                                                      limit  => 10);
    foreach my $builder_name ($config->get_builders) {
        my %extra_attrs = (status => 'idle');
        foreach my $pkg (@compiling_packages) {
            if ($pkg->{builder} eq $builder_name) {
                my %source_pkg_attrs = $packagedb->get_source_package_by_id($pkg->{source_package_id});
                $extra_attrs{status}  = 'compiling';
                $extra_attrs{package} = { %source_pkg_attrs };
                $extra_attrs{since}   = $pkg->{compilation_started_at};
            }
        }
        push @builder_list,
             { $config->get_builder_config($builder_name),
               %extra_attrs };
    }

    # Latest compilation failures --------------------------------------------
    my @failed_compilations = ();
    my @failed_compilation_queue = $packagedb->
                        get_compilation_queue(status => 'compilationfailed',
                                              limit  => 10);
    foreach my $comp (@failed_compilation_queue) {
        my %source_pkg_attrs =
            $packagedb->get_source_package_by_id($comp->{source_package_id});
        push @failed_compilations, {
            %$comp,
            package => { %source_pkg_attrs },
        };
    }

    # Latest compiled packages -----------------------------------------------
    my @latest_compilations = ();
    my @latest_compilation_queue = $packagedb->
                        get_compilation_queue(status => 'compiled',
                                              limit  => 10);
    foreach my $comp (@latest_compilation_queue) {
        my %source_pkg_attrs =
            $packagedb->get_source_package_by_id($comp->{source_package_id});
        push @latest_compilations, {
            %$comp,
            package => { %source_pkg_attrs },
        };
    }

    # Print everything -------------------------------------------------------
    $self->show_view('index.tmpl',
                     {config              => $config,
                      packages            => \@readable_packages,
                      unreadable_packages => \@unreadable_packages,
                      compilation_queue   => \@pending_compilations,
                      builders            => \@builder_list,
                      failed_compilations => \@failed_compilations,
                      latest_compilations => \@latest_compilations,
                      rm                  => join(", ", $self->query->param('rm'))});
}

sub approve {
    my ($self) = @_;

    # Find the package. The field will be "package-N", where N is an integer
    my ($field_name) = grep /^package-\d+$/, $self->query->param;
    $field_name =~ /^package-(\d+)$/;
    my $pkg_id = $1;
    $self->approve_package($self->query->param("package-$pkg_id"),
                           priority => $self->query->param("priority-$pkg_id"),
                           section  => $self->query->param("section-$pkg_id"));
    if ($self->error_list) {
        my $r = $self->show_view('error.tmpl',
                                 {errors => [$self->error_list]});
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

sub show_build_log {
    my ($self) = @_;

    # Force it to be a number
    my $request_id = 0 + $self->query->param('id');
    my $pdb    = Arepa::PackageDb->new($config->get_key('package_db'));
    eval {
        $pdb->get_compilation_request_by_id($request_id);
    };
    if ($EVAL_ERROR) {
        return $self->show_view('error.tmpl',
                                {errors => [{output => "No such compilation request: '$request_id'"}]});
    }
    else {
        my $build_log_path =
                        File::Spec->catfile($config->get_key('dir:build_logs'),
                                            $request_id);
        open F, $build_log_path or do {
            return $self->show_view('error.tmpl',
                                    {errors => [{output => "Can't read build log for compilation request '$request_id' from '$build_log_path'"}]});
        };
        my $build_log_contents = join("", <F>);
        close F;
        return "<pre>$build_log_contents</pre>";
    }
}

sub requeue {
    my ($self) = @_;

    # Force it to be a number
    my $request_id = 0 + $self->query->param('id');
    my $pdb    = Arepa::PackageDb->new($config->get_key('package_db'));
    eval {
        $pdb->get_compilation_request_by_id($request_id);
    };
    if ($EVAL_ERROR) {
        return $self->show_view('error.tmpl',
                                {errors => [{output => "No such compilation request: '$request_id'"}]});
    }
    else {
        $pdb->mark_compilation_pending($request_id);
        $self->_redirect("arepa.cgi");
    }
}


sub approve_package {
    my ($self, $changes_file_path, %opts) = @_;

    # Only get the file basename, and search for it in the incoming directory
    my $path = $config->get_key('upload_queue:path')."/".basename($changes_file_path);
    my $changes_file = Parse::Debian::PackageDesc->new($path);
    my $distribution = $changes_file->distribution;

    # Add the source package to the repo
    my $package_revision_base_name = $changes_file->source."_".
                                        $changes_file->version;
    my $source_file_path = $package_revision_base_name.".dsc";
    my $repository = Arepa::Repository->new($config_path);
    my $source_pkg_id = $repository->insert_source_package(
                                    $config->get_key('upload_queue:path')."/".
                                                $source_file_path,
                                    $distribution,
                                    %opts);
    if (!$source_pkg_id) {
        $self->add_error("Couldn't approve source package '$source_file_path'.",
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
                $self->add_error("Can't delete '$file_path'.");
            }
        }
        # Changes file itself
        if (! unlink($path)) {
            $self->add_error("Can't delete '$path'.");
        }

        # If everything went fine, add the source package to the compilation
        # queue
        my $farm = Arepa::BuilderFarm->new($config_path);
        $farm->request_package_compilation($source_pkg_id);

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
