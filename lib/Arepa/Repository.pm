package Arepa::Repository;

use strict;
use warnings;

use Carp qw(croak);

use Parse::Debian::PackageDesc;
use Arepa::Config;
use Arepa::PackageDb;

sub new {
    my ($class, $config_path) = @_;

    my $config = Arepa::Config->new($config_path);
    my $self = bless {
        config_path => $config_path,
        config      => $config,
        package_db  => Arepa::PackageDb->new($config->get_key('package_db')),
    }, $class;

    return $self;
}

sub config_key_exists {
    my ($self, $key) = @_;
    return $self->{config}->key_exists($key);
}

sub get_config_key {
    my ($self, $key) = @_;
    return $self->{config}->get_key($key);
}

sub get_distributions {
    my ($self) = @_;

    my $repository_config_file = $self->get_config_key('repository:path');
    my $distributions_config_file = "$repository_config_file/conf/distributions";
    open F, $distributions_config_file or croak "Can't open configuration file ";
    my ($line, $repo_attrs, @repos);
    while ($line = <F>) {
        if ($line =~ /^\s*$/) {
            push @repos, $repo_attrs if %$repo_attrs;
            $repo_attrs = {};
        }
        elsif ($line =~ /^([^:]+):\s+(.+)/i) {
            $repo_attrs->{lc($1)} = $2;
        }
    }
    push @repos, $repo_attrs if %$repo_attrs;
    close F;
    return @repos;
}

sub get_architectures {
    my ($self) = @_;

    my @archs;
    foreach my $repo ($self->get_distributions) {
        foreach my $arch (split(/\s+/, $repo->{architectures})) {
            push @archs, $arch unless grep { $arch eq $_ }
                                           @archs;
        }
    }
    return @archs;
}

sub insert_source_package {
    my ($self, $dsc_file, $distro, %user_opts) = @_;

    use Parse::Debian::PackageDesc;
    my $parsed_dsc = Parse::Debian::PackageDesc->new($dsc_file);
    my %args = (name         => $parsed_dsc->name,
                full_version => $parsed_dsc->version,
                architecture => $parsed_dsc->architecture,
                distribution => $distro);

    if (exists $user_opts{comments}) {
        $args{comments} = $user_opts{comments};
        delete $user_opts{comments};
    }

    my $canonical_distro = $distro;
    if ($user_opts{canonical_distro}) {
        $canonical_distro = $user_opts{canonical_distro};
        delete $user_opts{canonical_distro};
    }

    my $r = $self->_execute_reprepro('includedsc',
                                     $canonical_distro,
                                     $dsc_file,
                                     %user_opts);
    if ($r) {
        return $self->{package_db}->insert_source_package(%args);
    }
    else {
        return 0;
    }
}

sub insert_binary_package {
    my ($self, $deb_file, $distro) = @_;

    return $self->_execute_reprepro('includedeb',
                                    $distro,
                                    $deb_file);
}

sub _shell_escape {
    my ($self, $arg) = @_;
    if (defined $arg) {
        $arg =~ s/'/\\'/go;
    }
    else {
        $arg = "";
    }
    return "'$arg'";
}

sub last_cmd_output {
    my ($self) = @_;
    $self->{last_cmd_output};
}

sub _execute_reprepro {
    my ($self, $mode, $distro, $file_path, %extra_args) = @_;

    my $repo_path = $self->get_config_key("repository:path");
    $mode      = $self->_shell_escape($mode);
    $distro    = $self->_shell_escape($distro);
    $file_path = $self->_shell_escape($file_path);
    # Extra arguments
    my $extra = "";
    foreach my $arg (keys %extra_args) {
        # Section and priority options are actually flipped in reprepro (that's
        # a reprepro bug)
        if ($arg eq 'section') {
            $extra .= " --priority " . $self->_shell_escape($extra_args{$arg});
        }
        elsif ($arg eq 'priority') {
            $extra .= " --section " . $self->_shell_escape($extra_args{$arg})
        }
        else {
            croak "Don't know anything about argument '$arg'";
        }
    }
    # GNUPG home directory
    if ($self->config_key_exists('web_ui:gpg_homedir')) {
        my $gpg_homedir = $self->get_config_key('web_ui:gpg_homedir');
        if (defined $gpg_homedir && $gpg_homedir) {
            $extra .= " --gnupghome '$gpg_homedir'";
        }
    }

    my $cmd = "reprepro -b$repo_path $extra $mode $distro $file_path 2>&1";
    my $umask = umask;
    umask($umask & 0707);           # Always allow group permissions
    $self->{last_cmd_output} = `$cmd`;
    my $status = $?;
    umask $umask;
    if ($status == 0) {
        return 1;
    }
    else {
        print STDERR "Reprepro command failed: '$cmd'\n";
        return 0;
    }
}

sub package_list {
    my ($self) = @_;

    my %pkg_list;
    my $repo_path = $self->get_config_key("repository:path");
    foreach my $codename (map { $_->{codename} } $self->get_distributions) {
        my $cmd = "reprepro -b$repo_path list $codename";
        open PIPE, "$cmd |";
        while (<PIPE>) {
            my ($distro, $comp, $arch, $pkg_name, $pkg_version) =
                /(.+)\|(.+)\|(.+): ([^ ]+) (.+)/;
            $pkg_list{$pkg_name}->{"$distro/$comp"}->{$pkg_version} ||= [];
            push @{$pkg_list{$pkg_name}->{"$distro/$comp"}->{$pkg_version}},
                 $arch;
        }
        close PIPE;
    }
    return %pkg_list;
}

1;

__END__

=head1 NAME

Arepa::Repository - Arepa repository access class

=head1 SYNOPSIS

 my $repo = Arepa::Repository->new('path/to/config.yml');
 my $value = $repo->get_config_key('repository:path');
 my @distros = $repo->get_distributions;
 my @archs = $repo->get_architectures;
 my $bool = $repo->insert_source_package($dsc_file, $distro);
 my $bool = $repo->insert_source_package($dsc_file, $distro,
                                         priority => 'optional',
                                         section  => 'perl');
 my $bool = $repo->insert_source_package($dsc_file, $distro,
                                         priority => 'optional',
                                         section  => 'perl',
                                         comments => 'Why this was approved',
                                         canonical_distro => 'lenny');
 my $bool = $repo->insert_binary_package($deb_file, $distro);
 my $text = $repo->last_cmd_output;

=head1 DESCRIPTION

This class represents a reprepro-managed APT repository. It allows you get
information about the repository and to insert new source and binary packages
in it.

It uses the Arepa configuration to get the repository path, and the own
repository reprepro configuration to figure out the distributions and
architectures inside it.

=head1 METHODS

=over 4

=item new($path)

Creates a new repository access object, using the configuration file in
C<$path>.

=item get_config_key($key)

Gets the configuration key C<$key> from the Arepa configuration.

=item get_distributions

Returns an array of hashrefs. Each hashref represents a distribution declared
in the repository C<conf/distributions> configuration file, and contains a key for every distribution attribute.

=item get_architectures

Returns a list of all the architectures mentioned in any of the repository
distributions.

=item insert_source_package($dsc_file, $distribution, %options)

Inserts the source package described by the given C<$dsc_file> in the
repository and the package database, for the given C<$distribution>. Priority
and section can be specified with the C<priority> and C<section> options in
C<%options>. Other possible options are C<comments> (comments about the source
package e.g. why it was added to the repo or its origin) and
C<canonical_distro> (the "canonical" distribution, that is the distribution in
your repository the source package should be added to, as opposed to the
distribution specified in the actual source package changes file).

=item insert_binary_package($deb_file, $distribution)

Inserts the given binary package C<$deb_file> in the repository, for the given
C<$distribution>.

=item last_cmd_output

Returns the text output of the last executed command. This can help debugging
problems.

=item package_list

Returns a data structure representing all the available packages in all the
known distributions. The data structure is a hash that looks like this:

 (foobar => { "lenny/main" => { "1.0-1" => ['source'] } },
  pkg2   => { "lenny/main" => { "1.0-1" => [qw(amd64 source)],
                                "1.0-2" => ['i386'], },
              "etch/contrib" =>
                              { "0.8-1" => [qw(i386 amd64 source) }
            },
  dhelp  => { "lenny/main" => { "0.6.15" => [qw(i386 source)] } },
 )

That is, the keys are the package names, and the values are another hash. This
hash has C<distribution/component> as keys, and hashes as values. These hashes
have available versions as keys, and a list of architectures as values.

=back

=head1 SEE ALSO

C<Arepa::BuilderFarm>, C<Arepa::PackageDb>, C<Arepa::Config>.

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
