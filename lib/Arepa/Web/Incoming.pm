package Arepa::Web::Incoming;

use strict;
use warnings;

use base 'Arepa::Web::Base';

use File::Basename;
use Parse::Debian::PackageDesc;
use Arepa::Repository;
use Arepa::BuilderFarm;

sub _approve_package {
    my ($self, $changes_file_path, %opts) = @_;

    # Only get the file basename, and search for it in the incoming directory
    my $path = $self->config->get_key('upload_queue:path') . "/" .
                    basename($changes_file_path);
    my $changes_file = Parse::Debian::PackageDesc->new($path);
    my $distribution = $changes_file->distribution;

    # Add the source package to the repo
    my $package_revision_base_name = $changes_file->source."_".
                                        $changes_file->version;
    my $source_file_path = $package_revision_base_name.".dsc";
    my $repository = Arepa::Repository->new($self->config_path);
    my $farm       = Arepa::BuilderFarm->new($self->config_path);

    # Calculate the canonical distribution. It's needed for the reprepro call.
    # If reprepro accepted "reprepro includesrc 'funnydistro' ...", having
    # 'funnydistro' in the AlsoAcceptFor list, this wouldn't be necessary. We
    # do have to pass the real source package distribution to
    # insert_source_package so the compilation targets are calculated properly
    my ($arch) = grep { $_ ne 'source' } $changes_file->architecture;
    my @builders = $farm->get_matching_builders($arch, $distribution);
    my $builder;
    foreach my $b (@builders) {
        my %builder_cfg = $self->config->get_builder_config($b);
        if (grep { $_ eq $distribution }
                 @{$builder_cfg{distribution_aliases}},
                 $builder_cfg{distribution}) {
            # There should be only one; if there's more than one, that's a
            # problem
            if ($builder) {
                $self->_add_error("There is more than one builder that " .
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
        my $canonical_distro =
                $self->config->get_builder_config_key($builder,
                                                      'distribution');

        $source_pkg_id = $repository->insert_source_package(
                             $self->config->get_key('upload_queue:path').
                                         "/".$source_file_path,
                             $distribution,
                             canonical_distro => $canonical_distro,
                             %opts);

        if ($source_pkg_id) {
            if (system("sudo -H -u arepa-master arepa sign >/dev/null") != 0) {
                $self->_add_error("Couldn't sign repositories, check your " .
                                    "'sudo' configuration and " .
                                    "the README file");
            }
        }
        else {
            $self->_add_error("Couldn't approve source package " .
                                "'$source_file_path'.",
                                $repository->last_cmd_output);
        }
    }
    else {
        $self->_add_error("Can't find any builder for $source_file_path " .
                            "($distribution/$arch)");
    }

    if ($self->_error_list) {
        return 0;
    }
    else {
        # If everything went fine, add the source package to the compilation
        # queue
        $farm->request_package_compilation($source_pkg_id);

        $self->_remove_uploaded_package($path);

        if ($self->_error_list) {
            return 0;
        }
    }

    return 1;
}

sub _remove_uploaded_package {
    my ($self, $changes_file_path) = @_;

    my $changes_file = Parse::Debian::PackageDesc->new($changes_file_path);
    # Remove all files from the pending queue
    # Files referenced by the changes file
    foreach my $file ($changes_file->files) {
        my $file_path = $self->config->get_key('upload_queue:path')."/".$file;
        if (-e $file_path && ! unlink($file_path)) {
            $self->add_error("Can't delete '$file_path'.");
        }
    }
    # Changes file itself
    if (! unlink($changes_file_path)) {
        $self->add_error("Can't delete '$changes_file_path'.");
    }
}

sub process {
    my ($self) = @_;

    my @field_ids = map { /^package-(\d+)$/; $1 }
                        grep /^package-\d+$/,
                             keys %{$self->tx->req->params->to_hash};
    foreach my $field_id (@field_ids) {
        if ($self->param("approve_all") ||
                    $self->param("approve-$field_id")) {
            $self->_approve_package(
                $self->param("package-$field_id"),
                priority => $self->param("priority-$field_id"),
                section  => $self->param("section-$field_id"),
                comments => $self->param("comments-$field_id"));
        }
        elsif ($self->param("reject-$field_id")) {
            my $changes_file_path = $self->param("package-$field_id");
            my $path = $self->config->get_key('upload_queue:path')."/".
                            basename($changes_file_path);
            $self->_remove_uploaded_package($path);
        }
    }
    if ($self->_error_list) {
        $self->vars(errors => [$self->_error_list]);
        $self->render('error');
    }
    else {
        $self->redirect_to('home');
    }
}

1;
