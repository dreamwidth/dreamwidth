package LJ::IncomingEmailHandle;
use strict;
use warnings;
use File::Temp ();

sub new {
    my ($class) = @_;
    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO incoming_email_handle (ieid, timerecv) VALUES (NULL, UNIX_TIMESTAMP())")
        or die "Failed to insert into incoming_email_handle: " . $dbh->errstr;
    my $id = $dbh->{'mysql_insertid'} or
        die "Got no ID from auto increment";
    return bless {
        id => $id,
    }, $class;
}

sub id {
    $_[0]{id};
}

sub mogkey {
    my $self = shift;
    return "ie:" . $self->id;
}

sub tempfh {
    my $self = shift;
    $self->_make_tempfile unless $self->{tempfh};
    return $self->{tempfh};
}

sub tempfilename {
    my $self = shift;
    $self->_make_tempfile unless $self->{tempfh};
    return "$self->{tempfh}"; # stringify it
}

sub _make_tempfile {
    my $self = shift;
    $self->{tempfh} = File::Temp->new(TEMPLATE => 'incemailXXXXX',
                                      DIR      => File::Spec->tmpdir,
                                      SUFFIX   => ".ieh$self->{id}");
}

sub append {
    my ($self, $buf) = @_;
    my $fh = $self->tempfh;
    print $fh $buf;
}

sub closetemp {
    my $self = shift;
    close($self->tempfh);
}

sub tempsize {
    my $self = shift;
    return -s $self->tempfilename;
}

sub insert_into_mogile {
    my $self = shift;
    my $size = $self->tempsize;
    my $mogfh = LJ::mogclient()->new_file($self->mogkey, "", $size)
        or die "Failed to get Mogile handle: " . LJ::mogclient()->errstr;
    open (my $fh, $self->tempfilename) or die "Failed to reopen tempfile: $!";
    my $buf;
    my $rv;
    while ($rv = sysread($fh, $buf, 64*1024)) {
        $mogfh->print($buf)
            or die "Error writing to mogile";
    }
    die "Error reading from tempfile: $!" unless defined $rv;
    $mogfh->close
        or die "Error closing mogile filehandle";
    return 1;
}

1;
