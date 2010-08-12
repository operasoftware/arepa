package Arepa::Web::Dashboard;

use strict;
use warnings;

use base 'Arepa::Web::Base';

use Parse::Debian::PackageDesc;
use Arepa::Config;
use Arepa::Repository;
use Arepa::BuilderFarm;

sub index {
    my ($self) = @_;

    # For backwards compatibility with old RSS URLs
    if ($self->param('rm') && $self->param('rm') eq 'public_rss') {
        return $self->redirect_to(controller => 'public', action => 'rss');
    }

    my @packages = ();
    if (opendir D, $self->config->get_key('upload_queue:path')) {
        @packages = grep /\.changes$/, readdir D;
        closedir D;
    }

    # Packages pending approval ----------------------------------------------
    my (@readable_packages, @unreadable_packages);
    my $gpg_dir = $self->config->get_key('web_ui:gpg_homedir');
    foreach my $package (@packages) {
        my $package_path =
                $self->config->get_key('upload_queue:path')."/".$package;
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
    my $packagedb =
            Arepa::PackageDb->new($self->config->get_key('package_db'));
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
    foreach my $builder_name ($self->config->get_builders) {
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
             { $self->config->get_builder_config($builder_name),
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

    my $is_synced;
    if ($self->config->key_exists('web_ui:check_remote_repo') &&
            $self->config->get_key('web_ui:check_remote_repo') &&
            $self->config->key_exists('repository:remote_path')) {
        my $r = system("sudo -H -u arepa-master arepa issynced >/dev/null");
        $is_synced = ($r == 0);
    }

    # Print everything -------------------------------------------------------
    $self->vars(config              => $self->config,
                packages            => \@readable_packages,
                unreadable_packages => \@unreadable_packages,
                compilation_queue   => \@pending_compilations,
                builders            => \@builder_list,
                failed_compilations => \@failed_compilations,
                latest_compilations => \@latest_compilations,
                is_synced           => $is_synced);

    $self->render(layout => 'default');
}

1;
