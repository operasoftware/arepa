package Arepa::PackageDb;

use Carp qw(croak);
use DBI;

use constant SOURCE_PACKAGE_FIELDS => qw(name full_version
                                         architecture distribution);
use constant COMPILATION_QUEUE_FIELDS => qw(source_package_id architecture
                                            distribution builder
                                            status compilation_requested_at);

sub new {
    my ($class, $path) = @_;

    my $self = bless {
        path => $path,
        dbh  => DBI->connect("dbi:SQLite:dbname=$path"),
    }, $class;

    # If the file is empty, it means it doesn't have the tables yet
    if (-z $path) {
        $self->create_db;
    }

    return $self;
}

sub default_timestamp {
    my ($self) = @_;

    my ($sec, $min, $hour, $mday, $mon, $year) = localtime;
    return "$year-$mon-$mday $hour:$min:$sec";
}

sub create_db {
    my ($self) = @_;
    $self->_dbh->do(<<EOSQL);
CREATE TABLE source_packages (id           INTEGER PRIMARY KEY,
                              name         VARCHAR(50),
                              full_version VARCHAR(20),
                              architecture VARCHAR(10),
                              distribution VARCHAR(30));
EOSQL
    $self->_dbh->do(<<EOSQL);
CREATE TABLE compilation_queue (id                       INTEGER PRIMARY KEY,
                                source_package_id        INTEGER,
                                architecture             VARCHAR(10),
                                distribution             VARCHAR(30),
                                builder                  VARCHAR(50),
                                status                   VARCHAR(20),
                                compilation_requested_at TIMESTAMP,
                                compilation_started_at   TIMESTAMP,
                                compilation_completed_at TIMESTAMP);
EOSQL
}

sub _dbh {
    my ($self) = @_;
    return $self->{dbh};
}

sub get_source_package_id {
    my ($self, $name, $full_version) = @_;

    my $sth = $self->_dbh->prepare("SELECT id FROM source_packages
                                             WHERE name = ?
                                               AND full_version = ?");
    $sth->execute($name, $full_version);
    $sth->bind_columns(\my $id);
    return $sth->fetch ? $id : undef;
}

sub get_source_package_by_id {
    my ($self, $id) = @_;

    my $fields = join(", ", SOURCE_PACKAGE_FIELDS);
    my $sth = $self->_dbh->prepare("SELECT $fields
                                      FROM source_packages
                                     WHERE id = ?");
    $sth->execute($id);
    $sth->bind_columns(\my $name, \my $fv, \my $arch, \my $distro);
    return $sth->fetch ? (id           => $id,
                          name         => $name,
                          full_version => $fv,
                          architecture => $arch,
                          distribution => $distro) :
                         croak "Can't find a source package with id '$id'";
}

sub insert_source_package {
    my ($self, %props) = @_;

    my (@fields, @field_values);
    foreach my $field (keys %props) {
        if (not grep { $_ eq $field } SOURCE_PACKAGE_FIELDS) {
            croak "Don't recognise field '$field'";
        }
    }

    my $sth = $self->_dbh->prepare("INSERT INTO source_packages (" .
                                        join(", ", keys %props) .
                                        ") VALUES (" .
                                        join(", ", map { "?" } keys %props) .
                                        ")");
    $sth->execute(values %props);
    return $self->_dbh->last_insert_id(undef, undef,
                                       qw(source_packages), undef);
}

sub request_compilation {
    my ($self, $source_id, $arch, $dist, $tstamp) = @_;
    $tstamp ||= $self->default_timestamp;

    # Check that the source package id is valid. We are not going to use the
    # returned value for anything, but it will die with an exception if the id
    # is not valid
    my %source_package = $self->get_source_package_by_id($source_id);

    my $sth = $self->_dbh->prepare("INSERT INTO compilation_queue (
                                                source_package_id,
                                                architecture,
                                                distribution,
                                                status,
                                                compilation_requested_at)
                                        VALUES (?, ?, ?, ?, ?)");
    $sth->execute($source_id, $arch, $dist, "pending", $tstamp);
}

sub get_compilation_queue {
    my ($self, %user_opts) = @_;
    my %opts = (%user_opts);

    my $fields = join(", ", COMPILATION_QUEUE_FIELDS);
    my ($condition, $limit) = ("", "");
    if (exists $opts{status}) {
        $condition = "WHERE status = " . $self->_dbh->quote($opts{status});
    }
    if (exists $opts{limit}) {
        $limit = "LIMIT " . $self->_dbh->quote($opts{limit});
    }
    my $sth = $self->_dbh->prepare("SELECT id, $fields
                                      FROM compilation_queue
                                           $condition
                                  ORDER BY compilation_requested_at
                                           $limit");
    $sth->execute;
    $sth->bind_columns(\my $id,
                       \my $source_id, \my $arch, \my $distro,
                       \my $builder,   \my $stat, \my $requested_at);
    my @queue = ();
    while ($sth->fetch) {
        push @queue, {id                       => $id,
                      source_package_id        => $source_id,
                      architecture             => $arch,
                      distribution             => $distro,
                      builder                  => $builder,
                      status                   => $stat,
                      compilation_requested_at => $requested_at}
    }
    return @queue;
}

sub mark_compilation_started {
    my ($self, $compilation_id, $tstamp) = @_;
    $tstamp ||= $self->default_timestamp;

    my $sth = $self->_dbh->prepare("UPDATE compilation_queue
                                       SET status                 = ?,
                                           compilation_started_at = ?
                                     WHERE id = ?");
    $sth->execute('compiling', $tstamp, $compilation_id);
}

sub mark_compilation_completed {
    my ($self, $compilation_id, $tstamp) = @_;
    $tstamp ||= $self->default_timestamp;

    my $sth = $self->_dbh->prepare("UPDATE compilation_queue
                                       SET status                   = ?,
                                           compilation_completed_at = ?
                                     WHERE id = ?");
    $sth->execute('compiled', $tstamp, $compilation_id);
}

sub mark_compilation_failed {
    my ($self, $compilation_id, $tstamp) = @_;
    $tstamp ||= $self->default_timestamp;

    my $sth = $self->_dbh->prepare("UPDATE compilation_queue
                                       SET status                   = ?,
                                           compilation_completed_at = ?
                                     WHERE id = ?");
    $sth->execute('compilationfailed', $tstamp, $compilation_id);
}

1;
