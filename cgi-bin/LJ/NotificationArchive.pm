# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

# This package is for managing a queue of archived notifications
# for a user.
# Henry Lyne 20070604

package LJ::NotificationArchive;

use strict;
use Carp qw(croak);
use LJ::NotificationItem;
use LJ::Event;

*new = \&instance;

my %singletons = ();

# constructor takes a $u
sub instance {
    my ( $class, $u ) = @_;

    croak "Invalid args to construct LJ::NotificationArchive" unless $class && $u;
    croak "Invalid user" unless LJ::isu($u);

    return $singletons{ $u->{userid} } if $singletons{ $u->{userid} };

    my $self = {
        uid   => $u->userid,
        count => undef,        # defined once ->count is loaded/cached
        items => undef,
    };

    $singletons{ $u->{userid} } = $self;

    return bless $self, $class;
}

# returns the user object associated with this queue
sub u {
    my $self = shift;
    return LJ::load_userid( $self->{uid} );
}

# returns all non-deleted Event objects for this user
# in a hashref of {queueid => event}
# optional arg: daysold = how many days back to retrieve notifications for
sub notifications {
    my $self    = shift;
    my $daysold = shift;

    croak "notifications is an object method"
        unless ( ref $self ) eq __PACKAGE__;

    return $self->_load($daysold);
}

# Returns a list of LJ::NotificationItems in this queue.
sub items {
    my $self = shift;

    croak "items is an object method"
        unless ( ref $self ) eq __PACKAGE__;

    return @{ $self->{items} } if defined $self->{items};

    my @qids = $self->_load;

    my @items = ();
    foreach my $qid (@qids) {
        push @items, LJ::NotificationItem->new( $self->u, $qid );
    }

    $self->{items} = \@items;

    return @items;
}

# load the events in this queue
sub _load {
    my $self = shift;

    return $self->{events} if $self->{loaded};

    my $u = $self->u
        or die "No user object";

    # is it memcached?
    my $qids;
    $qids = LJ::MemCache::get( $self->_memkey ) and return @$qids;

    # State of 'D' means Deleted
    my $sth = $u->prepare( "SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime "
            . "FROM notifyarchive WHERE userid=? AND state!='D'" );
    $sth->execute( $u->{userid} );
    die $sth->errstr if $sth->err;

    my @items = ();
    while ( my $row = $sth->fetchrow_hashref ) {
        my $qid = $row->{qid};

        # load this item into process cache so it's ready to go
        my $qitem = LJ::NotificationItem->new( $u, $qid );
        $qitem->absorb_row($row);

        push @items, $qitem;
    }

    # sort based on create time
    @items = sort { $a->when_unixtime <=> $b->when_unixtime } @items;

    # get sorted list of ids
    my @item_ids = map { $_->qid } @items;

    LJ::MemCache::set( $self->_memkey, \@item_ids );

    return @item_ids;
}

sub _memkey {
    my $self   = shift;
    my $userid = $self->{uid};
    return [ $userid, "inbox:archive:$userid" ];
}

# deletes an Event that is queued for this user
# args: Queue ID to remove from queue
sub delete_from_queue {
    my ( $self, $qid ) = @_;

    croak "delete_from_queue is an object method"
        unless ( ref $self ) eq __PACKAGE__;

    croak "no queueid passed to delete_from_queue" unless int($qid);

    my $u = $self->u
        or die "No user object";

    $self->_load;

    # if this event was returned from our queue we should have
    # its qid stored in our events hashref
    delete $self->{events}->{$qid};

    $u->do( "UPDATE notifyqueue SET state='D' WHERE qid=?", undef, $qid );
    die $u->errstr if $u->err;

    # invalidate caches
    $self->expire_cache;

    return 1;
}

sub expire_cache {
    my $self = shift;

    $self->{count} = undef;
    $self->{items} = undef;

    LJ::MemCache::delete( $self->_memkey );
}

# This will enqueue an event object
# Returns the queue id
sub enqueue {
    my ( $self, %opts ) = @_;

    my $evt = delete $opts{event};
    croak "No event" unless $evt;
    croak "Extra args passed to enqueue" if %opts;

    my $u = $self->u or die "No user";

    # get a qid
    my $qid = LJ::alloc_user_counter( $u, 'Q' )
        or die "Could not alloc new queue ID";

    my %item = (
        qid        => $qid,
        userid     => $u->{userid},
        journalid  => $evt->u->{userid},
        etypeid    => $evt->etypeid,
        arg1       => $evt->arg1,
        arg2       => $evt->arg2,
        state      => ' ',
        createtime => time()
    );

    # write to archive table
    $u->do(
        "INSERT INTO notifyarchive ("
            . join( ",", keys %item )
            . ") VALUES ("
            . join( ",", map { '?' } values %item ) . ")",
        undef,
        values %item
    ) or die $u->errstr;

    $self->{events}->{$qid} = $evt;

    return $qid;
}

1;
