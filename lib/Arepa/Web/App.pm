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
use File::stat;
use Digest::MD5;
use POSIX qw(strftime);

use base qw(CGI::Application);
use CGI::Application::Plugin::TT;
use CGI::Application::Plugin::Authentication;
use CGI::Application::Plugin::Session;
use YAML;
use Data::Dumper;
use XML::RSS;

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
    return ($users{$user} eq Digest::MD5::md5_hex($password));
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
    $self->authen->protected_runmodes(qr/^(?!public_)/);
    $self->start_mode('home');
    $self->mode_param('rm');
    $self->run_modes(
        map { ($_ => $_) }
            qw(home process process_all build_log requeue view_repo logout
               public_rss)
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
                                  output => $output || ""};
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
                                              order  => "compilation_completed_at DESC",
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
                                              order  => "compilation_requested_at DESC",
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

sub process {
    my ($self) = @_;

    # Find the package. The field will be "package-N", where N is an integer
    my ($field_name) = grep /^package-\d+$/, $self->query->param;
    $field_name =~ /^package-(\d+)$/;
    my $pkg_id = $1;
    if ($self->query->param("approve")) {
        $self->approve_package(
            $self->query->param("package-$pkg_id"),
            priority => $self->query->param("priority-$pkg_id"),
            section  => $self->query->param("section-$pkg_id"),
            comments => $self->query->param("comments-$pkg_id"));
    }
    elsif ($self->query->param("reject")) {
        my $changes_file_path = $self->query->param($field_name);
        my $path = $config->get_key('upload_queue:path')."/".
                        basename($changes_file_path);
        $self->remove_uploaded_package($path);
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

sub process_all {
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

sub build_log {
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

sub view_repo {
    my ($self) = @_;

    my $repository = Arepa::Repository->new($config_path);
    my $pdb = Arepa::PackageDb->new($config->get_key('package_db'));

    # Print everything -------------------------------------------------------
    my %packages = $repository->package_list;
    my %comments = ();
    foreach my $pkg (keys %packages) {
        foreach my $comp (keys %{$packages{$pkg}}) {
            foreach my $version (keys %{$packages{$pkg}->{$comp}}) {
                if (grep { $_ eq 'source' }
                         @{$packages{$pkg}->{$comp}->{$version}}) {
                    my $id = $pdb->get_source_package_id($pkg, $version);
                    my %source_pkg = $pdb->get_source_package_by_id($id);
                    $comments{$pkg}->{$version} = $source_pkg{comments};
                }
            }
        }
    }
    $self->show_view('repo.tmpl',
                     { packages => \%packages,
                       comments => \%comments });
}


sub remove_uploaded_package {
    my ($self, $changes_file_path) = @_;

    my $changes_file = Parse::Debian::PackageDesc->new($changes_file_path);
    # Remove all files from the pending queue
    # Files referenced by the changes file
    foreach my $file ($changes_file->files) {
        my $file_path = $config->get_key('upload_queue:path')."/".$file;
        if (-e $file_path && ! unlink($file_path)) {
            $self->add_error("Can't delete '$file_path'.");
        }
    }
    # Changes file itself
    if (! unlink($changes_file_path)) {
        $self->add_error("Can't delete '$changes_file_path'.");
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
    my $farm       = Arepa::BuilderFarm->new($config_path);

    # Calculate the canonical distribution. It's needed for the reprepro call.
    # If reprepro accepted "reprepro includesrc 'funnydistro' ...", having
    # 'funnydistro' in the AlsoAcceptFor list, this wouldn't be necessary. We
    # do have to pass the real source package distribution to
    # insert_source_package so the compilation targets are calculated properly
    my ($arch) = grep { $_ ne 'source' } $changes_file->architecture;
    my @builders = $farm->get_matching_builders($arch, $distribution);
    my $builder;
    foreach my $b (@builders) {
        my %builder_cfg = $config->get_builder_config($b);
        if (grep { $_ eq $distribution }
                 @{$builder_cfg{distribution_aliases}},
                 $builder_cfg{distribution}) {
            # There should be only one; if there's more than one, that's a
            # problem
            if ($builder) {
                $self->add_error("There is more than one builder that " .
                                    "specifies '$distribution' as alias. " .
                                    "That's not correct! One of them " .
                                    "should specify it as bin_nmu_for");
                $builder = undef;
                last;
            }
            $builder = $b;
        }
    }
    my $source_pkg_id;
    if ($builder) {
        my $canonical_distro = $config->get_builder_config_key($builder,
                                                               'distribution');

        $source_pkg_id = $repository->insert_source_package(
                                     $config->get_key('upload_queue:path').
                                                 "/".$source_file_path,
                                     $distribution,
                                     canonical_distro => $canonical_distro,
                                     %opts);

        if ($source_pkg_id) {
            if (system("sudo -H -u arepa-master arepa sign >/dev/null") != 0) {
                $self->add_error("Couldn't sign repositories, check your " .
                                    "'sudo' configuration and " .
                                    "the README file");
            }
        }
        else {
            $self->add_error("Couldn't approve source package " .
                                "'$source_file_path'.",
                                $repository->last_cmd_output);
        }
    }
    else {
        $self->add_error("Can't find any builder for $source_file_path " .
                            "($distribution/$arch)");
    }

    if ($self->error_list) {
        return 0;
    }
    else {
        # If everything went fine, add the source package to the compilation
        # queue
        $farm->request_package_compilation($source_pkg_id);

        $self->remove_uploaded_package($path);

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

# Assuming here that the contents of the upload queue are not really secret,
# hence this runmode is not protected
sub public_rss {
    my ($self) = @_;

    my $rss = XML::RSS->new(version => '2.0');
    $rss->channel(
        title        => "Arepa upload queue",
        link         => "http://search.cpan.org/~opera/",
        description  => "Packages waiting to be approved for your Debian repository",
        dc => {
            date       => '2010-06-02T09:15+00:00',
            subject    => "Software distribution",
            creator    => 'estebanm@opera.com',
            language   => 'en-us',
        },
        syn => {
            updatePeriod     => "hourly",
            updateBase       => "1901-01-01T00:00+00:00",
        },
        taxo => [
            'http://dmoz.org/Computers/Software/Operating_Systems/Linux/Distributions/Debian/',
        ]
    );


    my @changes_files = ();
    if (opendir D, $config->get_key('upload_queue:path')) {
        @changes_files = grep /\.changes$/, readdir D;
        closedir D;
    }
    my @packages;
    my $gpg_dir = $config->get_key('web_ui:gpg_homedir');
    foreach my $changes_file (@changes_files) {
        my $changes_file_path = $config->get_key('upload_queue:path')."/".
                                    $changes_file;
        eval {
            push @packages,
                 Parse::Debian::PackageDesc->new($changes_file_path,
                                                 gpg_homedir => $gpg_dir);
        };
    }

    foreach my $pkg (@packages) {
        my $signature_info = "";
        if ($pkg->signature_id) {
            $signature_info = "It is signed with id " .
                                $pkg->signature_id . ".";
            if (! $pkg->correct_signature) {
                $signature_info .= " The signature is <strong>NOT " .
                                    "VALID</strong>";
            }
        }
        else {
            $signature_info = "It is <strong>NOT SIGNED</strong>.";
        }

        $rss->add_item(
            title       => $pkg->name . " " . $pkg->version . " for " .
                            $pkg->distribution,
            link        => $config->get_key('web_ui:base_url') .
                            "/" . $pkg->name,
            description => $pkg->name . " " . $pkg->version .
                            " was uploaded by " .
                            $self->_retarded_escape($pkg->maintainer) .
                            ".<br/>" .  $signature_info,
            pubDate     => strftime("%a, %d %b %Y %H:%M:%S %z",
                                    localtime(stat($pkg->path)->mtime)),
        );
    }

    return $rss->as_string;
}

sub _retarded_escape {
    my ($self, $value) = @_;

    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return $value;
}

sub _redirect {
    my ($self, $url) = @_;
    $self->header_type('redirect');
    $self->header_props(-url => $url);
}

1;

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
# End:
# vim: expandtab tabstop=4 shiftwidth=4 shiftround

__END__

=head1 NAME

Arepa::Web::App - CGI::Application app for Debian repository management

=head1 SYNOPSIS

 use Arepa::Web::App;
 Arepa::Web::App->run;

=head1 CONFIGURATION

C</etc/arepa/config.yml>

=head1 DEPENDENCIES

=over 4

=item

C<CGI::Application>

=item

C<CGI::Application::Plugin::Authentication>

=item

C<CGI::Application::Plugin::TT>

=back

=head1 SEE ALSO

=over 4

=item

C<Parse::Debian::Packages>

=item

C<CGI::Application>

=back

=head1 AUTHOR

Esteban Manchado Velázquez <estebanm@opera.com>.

=head1 LICENSE AND COPYRIGHT

This code is offered under the Open Source BSD license.

Copyright (c) 2010, Opera Software. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

=over 4

=item

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

=item

Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

=item

Neither the name of Opera Software nor the names of its contributors may
be used to endorse or promote products derived from this software without
specific prior written permission.

=back

=head1 DISCLAIMER OF WARRANTY

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
