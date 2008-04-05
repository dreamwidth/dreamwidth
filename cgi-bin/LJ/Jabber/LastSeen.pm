package LJ::Jabber::LastSeen;

use strict;
use warnings;
no warnings 'redefine';

use Carp qw(croak);

use LJ::MemCache;

=head1 PACKAGE METHODS

=head2 $obj = LJ::Jabber::LastSeen->new( $u )

Loads a Jabber last seen object from Memcache, or failing that from the database.

Requires one arguments, a LJ::User object (or something that's similar)

=cut

sub new {
    my $class = shift;
    return undef;
    my ($u, $resource) = @_;

    croak "No user" unless $u;

    my $self = {
        u        => $u,
    };

    bless $self, $class;

    my $userid = $u->id;

    my $memcached = LJ::MemCache::get( [$userid, "jablastseen:$userid"] );

    if ($memcached) {
        %$self = (%$self, %$memcached);
        return $self;
    }

    my $dbh = $u->writer() or die "No db";

    my $row = $dbh->selectrow_hashref("SELECT presence, time, motd_ver FROM jablastseen WHERE userid=?",
                                      undef, $self->u->id);

    die $dbh->errstr if $dbh->errstr;

    return unless $row;

    %$self = (%$self, %$row);

    LJ::MemCache::set( [$userid, "jablastseen:$userid"],
                       {
                           presence  => $self->presence,
                           time      => $self->time,
                           motd_ver  => $self->motd_ver,
                       } );

    return $self;
}

=head2 $obj = LJ::Jabber::Presence->create( %opts );

Creates a Jabber::Presence object from %opts and saves it to the database.

Options are as follows:

=over

=item u

LJ::User object (or similar) representing the user this presence applies to

=item presence

Raw XML string of presence data for this user's presence.

=item motd_ver

Integer field for holding motd version number, so we only show a user the motd if they haven't seen it before.

=back

=cut

sub create {
    my $class = shift;
    my %opts = @_;
    return undef;
    my $u    = delete( $opts{u} )        or croak "No user";
    my $presence = delete( $opts{presence} );
    my $motd_ver   = delete( $opts{motd_ver} );

    my $time = CORE::time;

    croak( "Unknown options: " . join( ',', keys %opts ) )
        if (keys %opts);

    my $userid = $u->id;

    my $self = bless {
                      u         => $u,
                      presence  => $presence,
                      time      => $time,
                      motd_ver  => $motd_ver,
                     }, $class;

    my $dbh = $u->writer() or die "No db";

    my $sth = $dbh->prepare( "INSERT INTO jablastseen (userid, presence, time, motd_ver) VALUES (?, ?, ?, ?)" );
    $sth->execute( $u->id, $presence, $time, $motd_ver );

    if ($sth->errstr) {
        die "Insertion error: " . $sth->errstr;
        return;
    }

    LJ::MemCache::set( [$userid, "jablastseen:$userid"],
                       {
                           presence  => $presence,
                           time      => $time,
                           motd_ver  => $motd_ver,
                       } );

    return $self;
}

=head1 OBJECT METHODS

=head2 $obj->u

=head2 $obj->presence

=head2 $obj->time

=head2 $obj->motd_ver

General purpose accessors for attributes on these objects.

=cut

sub u        { $_[0]->{u} }
sub presence { $_[0]->{presence} }
sub time     { $_[0]->{time} }
sub motd_ver { $_[0]->{motd_ver} }

=head2 $obj->set_presence( $val )

=head2 $obj->set_motd_ver( $val )

Setters for values on these objects.

=cut

sub set_presence {
    my $self = shift;
    my $val = shift;

    croak( "Didn't pass in a defined value to set" )
        unless defined $val;

    $self->{presence} = $val;
    $self->{time} = CORE::time;

    $self->_save( 'presence', 'time' );

    return $val;
}

sub set_motd_ver {
    my $self = shift;
    my $val = shift;

    croak "Didn't pass in a defined value to set"
        unless defined $val;

    $self->{motd_ver} = $val;
    $self->{time} = CORE::time;

    $self->_save( 'motd_ver', 'time' );

    return $val;
}

# Internal functions

my %savable_cols = map { ($_, 1) } qw(presence motd_ver time);

sub _save {
    my $self = shift;

    return unless @_;

    my @bad_cols = grep {!$savable_cols{$_}} @_;
    die "Cannot save cols " . join( ',', @bad_cols ) . "."
        if @bad_cols;

    my $userid = $self->u->id;

    my $dbh = $self->u->writer() or die "No db";

    my $sql = "UPDATE jablastseen SET " .
              join( ', ', map { "$_ = " . (defined($self->{$_}) ? "?" : "NULL") } @_ ) .
              " WHERE userid=?";

    my @placeholders = map { defined($self->{$_}) ? $self->{$_} : () } @_;

    $dbh->do( $sql, undef, @placeholders, $userid );

    die "Database update failed: " . $dbh->errstr
        if $dbh->errstr;

    LJ::MemCache::delete( [$userid, "jablastseen:$userid"], 0 );
}

1;
