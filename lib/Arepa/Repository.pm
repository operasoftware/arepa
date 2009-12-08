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
    my ($self, $dsc_file, $distro) = @_;

    use Parse::Debian::PackageDesc;
    my $parsed_dsc = Parse::Debian::PackageDesc->new($dsc_file);
    my %args = (name         => $parsed_dsc->name,
                full_version => $parsed_dsc->version,
                architecture => $parsed_dsc->architecture,
                distribution => $distro);

    my $r = $self->_execute_reprepro('includedsc',
                                     $args{distribution},
                                     $dsc_file);
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
    $arg =~ s/'/\\'/go;
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

=item insert_source_package($dsc_file, $distribution)

Inserts the source package described by the given C<$dsc_file> in the
repository and the package database, for the fiven C<$distribution>.

=item insert_binary_package($deb_file, $distribution)

Inserts the given binary package C<$deb_file> in the repository, for the given
C<$distribution>.

=item last_cmd_output

Returns the text output of the last executed command. This can help debugging
problems.

=back

=head1 SEE ALSO

C<Arepa::BuilderFarm>, C<Arepa::PackageDb>, C<Arepa::Config>.
