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

# This is a class representing a notification that came out of an
# LJ::NotificationInbox. You can tell it to mark itself as
# read/unread, delete it, and get the event that it contains out of
# it.
# Mischa Spiegelmock, 05/2006

package LJ::NotificationItem;
use strict;
use warnings;
no warnings "redefine";

use LJ::NotificationInbox;
use LJ::Event;
use Carp qw(croak);

*new = \&instance;

# parameters: user, notification inbox id
sub instance {
    my ( $class, $u, $qid ) = @_;

    my $singletonkey = $qid;

    $u->{_inbox_items} ||= {};
    return $u->{_inbox_items}->{$singletonkey} if $u->{_inbox_items}->{$singletonkey};

    my $self = {
        userid  => $u->id,
        qid     => $qid,
        state   => undef,
        event   => undef,
        when    => undef,
        _loaded => 0,
    };

    $u->{_inbox_items}->{$singletonkey} = $self;

    return bless $self, $class;
}

# returns whose notification this is
*u = \&owner;
sub owner { LJ::load_userid( $_[0]->{userid} ) }

# returns this item's id in the notification queue
sub qid { $_[0]->{qid} }

# returns true if this item really exists
sub valid {
    my $self = shift;

    return undef unless $self->u && $self->qid;
    $self->_load unless $self->{_loaded};

    return $self->event;
}

# returns title of this item
sub title {
    my $self = shift;
    return "(Invalid event)" unless $self->event;

    my %opts = @_;
    my $mode = delete $opts{mode};
    croak "Too many args passed to NotificationItem->as_html" if %opts;

    $mode = "html" unless $mode && $LJ::DEBUG{"esn_inbox_titles"};

    if ( $mode eq "html" ) {
        return eval { $self->event->as_html( $self->u ) } || $@;
    }
}

# returns contents of this item for user u
sub as_html {
    my $self = shift;
    croak "Too many args passed to NotificationItem->as_html" if scalar @_;
    return "(Invalid event)" unless $self->event;
    return eval { $self->event->content( $self->u ) } || $@;
}

sub as_html_summary {
    my $self = shift;
    croak "Too many args passed to NotificationItem->as_html_summary" if scalar @_;
    return "(Invalid event)" unless $self->event;
    return eval { $self->event->content_summary( $self->u ) } || $@;
}

# returns the event that this item refers to
sub event {
    my $self = shift;

    $self->_load unless $self->{_loaded};

    return $self->{event};
}

# loads this item
sub _load {
    my $self = shift;

    my $qid = $self->qid;
    my $u   = $self->owner;

    return if $self->{_loaded};

    # load info for all the currently instantiated singletons
    # get current singleton qids
    $u->{_inbox_items} ||= {};
    my @qids = map { $_->qid } values %{ $u->{_inbox_items} };

    my $bind = join( ',', map { '?' } @qids );

    my $sth = $u->prepare( "SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime "
            . "FROM notifyqueue WHERE userid=? AND qid IN ($bind)" );
    $sth->execute( $u->id, @qids );
    die $sth->errstr if $sth->err;

    my @items;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $qid = $row->{qid} or next;
        my $singleton = $u->{_inbox_items}->{$qid} or next;

        push @items, $singleton->absorb_row($row);
    }
}

# fills in a skeleton item from a database row hashref
sub absorb_row {
    my ( $self, $row ) = @_;

    $self->{_loaded} = 1;

    $self->{state} = $row->{state};
    $self->{when}  = $row->{createtime};

    my $evt = LJ::Event->new_from_raw_params( $row->{etypeid}, $row->{journalid}, $row->{arg1},
        $row->{arg2} );
    $self->{event} = $evt;

    return $self;
}

# returns when this event happened (or got put in the inbox)
sub when_unixtime {
    my $self = shift;

    $self->_load unless $self->{_loaded};

    return $self->{when};
}

# returns the state of this item
sub _state {
    my $self = shift;

    $self->_load unless $self->{_loaded};

    return $self->{state};
}

# returns if this event is marked as read
sub read {
    return 0 unless defined $_[0]->_state;
    return $_[0]->_state eq 'R';
}

# returns if this event is marked as unread
sub unread {
    return 0 unless defined $_[0]->_state;
    return $_[0]->_state eq 'N';
}

# delete this item from its inbox
sub delete {
    my $self = shift;
    return unless $self->owner;
    my $inbox = $self->owner->notification_inbox;

    # delete from the inbox so the inbox stays in sync
    my $ret = $inbox->delete_from_queue($self);
    %$self = ();
    return $ret;
}

# mark this item as read
sub mark_read {
    my $self = shift;

    # do nothing if it's already marked as read
    return if $self->read;
    $self->_set_state('R');
}

# mark this item as read
sub mark_unread {
    my $self = shift;

    # do nothing if it's already marked as unread
    return if $self->unread;
    $self->_set_state('N');
}

# sets the state of this item
sub _set_state {
    my ( $self, $state ) = @_;

    $self->owner->do( "UPDATE notifyqueue SET state=? WHERE userid=? AND qid=?",
        undef, $state, $self->owner->id, $self->qid )
        or die $self->owner->errstr;
    $self->{state} = $state;

    # expire unread cache
    my $userid = $self->u->id;
    my $memkey = [ $userid, "inbox:newct:${userid}" ];
    LJ::MemCache::delete($memkey);
}

# JSON output implementation for NotificationItem objects
sub TO_JSON {
    my $self = shift;
    my $json = {
        title     => $self->title,
        content   => $self->as_html,
        unread    => $self->unread,
        timestamp => $self->when_unixtime

    };
}
