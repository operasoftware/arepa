package Arepa::Repository;

use strict;
use warnings;

use Carp qw(croak);

use lib qw(../Parse-Debian-Changes/trunk/lib/);
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

sub get_config_key {
    my ($self, $key) = @_;
    return $self->{config}->get_key($key);
}

sub get_repositories {
    my ($self, $key) = @_;

    my $repository_config_file = $self->get_config_key('repository:path');
    my $distributions_config_file = "$repository_config_file/conf/distributions";
    open F, $distributions_config_file or croak "Can't open configuration file ";
    my ($line, $repo_attrs, @repos);
    while ($line = <F>) {
        if ($line =~ /^\s*$/) {
            use Data::Dumper;
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

sub get_repository_architectures {
    my ($self) = @_;

    my @archs;
    foreach my $repo ($self->get_repositories) {
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

    my $cmd = "reprepro -b$repo_path $mode $distro $file_path $extra 2>&1";
    $self->{last_cmd_output} = `$cmd`;
    my $status = $?;
    return ($status == 0);
}

1;
