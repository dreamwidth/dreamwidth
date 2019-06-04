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

package LJ::Subscription;
use strict;
use Carp qw(croak confess);
use LJ::NotificationMethod;
use LJ::Typemap;
use LJ::Event;
use LJ::Subscription::Pending;

use constant {
    INACTIVE => 1 << 0,    # user has deactivated
    DISABLED => 1 << 1,    # system has disabled
    TRACKING => 1 << 2,    # subs in the "notices" category
};

my @subs_fields = qw(userid subid is_dirty journalid etypeid arg1 arg2
    ntypeid createtime expiretime flags);

sub new_by_id {
    my ( $class, $u, $subid ) = @_;
    croak "new_by_id requires a valid 'u' object"
        unless LJ::isu($u);
    return if $u->is_expunged;

    croak "invalid subscription id passed"
        unless defined $subid && int($subid) > 0;

    my $row = $u->selectrow_hashref(
        "SELECT userid, subid, is_dirty, journalid, etypeid, "
            . "arg1, arg2, ntypeid, createtime, expiretime, flags "
            . "FROM subs WHERE userid=? AND subid=?",
        undef, $u->{userid}, $subid
    );
    die $u->errstr if $u->err;

    return $class->new_from_row($row);
}

sub freeze {
    my $self = shift;
    return "subid-" . $self->owner->{userid} . '-' . $self->id;
}

# can return either a LJ::Subscription or LJ::Subscription::Pending object
sub thaw {
    my ( $class, $data, $u, $POST ) = @_;

    # valid format?
    return undef unless ( $data =~ /^(pending|subid) - $u->{userid} .+ ?(-old)?$/x );

    my ( $type, $userid, $subid ) = split( "-", $data );

    return LJ::Subscription::Pending->thaw( $data, $u, $POST ) if $type eq 'pending';
    die "Invalid subscription data type: $type" unless $type eq 'subid';

    unless ($u) {
        my $subuser = LJ::load_userid($userid);
        die "no user" unless $subuser;
        $u = LJ::get_authas_user($subuser);
        die "Invalid user $subuser->{user}" unless $u;
    }

    return $class->new_by_id( $u, $subid );
}

sub pending          { 0 }
sub default_selected { $_[0]->active && $_[0]->enabled }

sub subscriptions_of_user {
    my ( $class, $u ) = @_;
    croak "subscriptions_of_user requires a valid 'u' object"
        unless LJ::isu($u);

    return if $u->is_expunged;
    return @{ $u->{_subscriptions} } if defined $u->{_subscriptions};

    my $sth =
        $u->prepare( "SELECT userid, subid, is_dirty, journalid, etypeid, "
            . "arg1, arg2, ntypeid, createtime, expiretime, flags "
            . "FROM subs WHERE userid=?" );
    $sth->execute( $u->{userid} );
    die $u->errstr if $u->err;

    my @subs;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @subs, LJ::Subscription->new_from_row($row);
    }

    $u->{_subscriptions} = \@subs;

    return @subs;
}

# Class method
# Look for a subscription matching the parameters: journalu/journalid,
#   ntypeid/method, event/etypeid, arg1, arg2
# Returns a list of subscriptions for this user matching the parameters
sub find {
    my ( $class, $u, %params ) = @_;

    my ( $etypeid, $ntypeid, $arg1, $arg2, $flags );

    if ( my $evt = delete $params{event} ) {
        $etypeid = LJ::Event->event_to_etypeid($evt);
    }

    if ( my $nmeth = delete $params{method} ) {
        $ntypeid = LJ::NotificationMethod->method_to_ntypeid($nmeth);
    }

    $etypeid ||= delete $params{etypeid};
    $ntypeid ||= delete $params{ntypeid};

    $flags = delete $params{flags};

    my $journalid = delete $params{journalid};
    $journalid ||= LJ::want_userid( delete $params{journal} ) if defined $params{journal};

    $arg1 = delete $params{arg1};
    $arg2 = delete $params{arg2};

    my $require_active = delete $params{require_active} ? 1 : 0;

    croak "Invalid parameters passed to ${class}->find" if keys %params;

    return () if defined $arg1 && $arg1 =~ /\D/;
    return () if defined $arg2 && $arg2 =~ /\D/;

    my @subs = $u->subscriptions;

    @subs = grep { $_->active && $_->enabled } @subs if $require_active;

    # filter subs on each parameter
    @subs = grep { $_->journalid == $journalid } @subs if defined $journalid;
    @subs = grep { $_->ntypeid == $ntypeid } @subs     if $ntypeid;
    @subs = grep { $_->etypeid == $etypeid } @subs     if $etypeid;
    if ( defined $flags ) {

        # check DISABLED and TRACKING flags, but not INACTIVE flag.
        @subs = grep { ( $flags & DISABLED ) == $_->disabled } @subs;
        @subs = grep { ( $flags & TRACKING ) == $_->is_tracking_category } @subs;
    }
    @subs = grep { $_->arg1 == $arg1 } @subs if defined $arg1;
    @subs = grep { $_->arg2 == $arg2 } @subs if defined $arg2;

    return @subs;
}

# Instance method
# Deactivates a subscription. If this is not a "tracking" subscription,
# it will delete it instead. Does nothing to disabled subscriptions.
sub deactivate {
    my $self = shift;

    my %opts  = @_;
    my $force = delete $opts{force};    # force-delete

    croak "Invalid args" if scalar keys %opts;

    my $subid = $self->id
        or croak "Invalid subsciption";

    my $u = $self->owner;

    # don't care about disabled subscriptions
    return if $self->disabled;

    # if it's the inbox method, deactivate/delete the other notification methods too
    my @to_remove = ();

    my @subs = $self->corresponding_subs;

    foreach my $subscr (@subs) {

        # Don't deactivate if the Inbox is always subscribed to
        my $always_checked = $subscr->event_class->always_checked ? 1 : 0;
        if ( $subscr->is_tracking_category && !$force ) {

            # delete non-inbox methods if we're deactivating
            if ( $subscr->method eq 'LJ::NotificationMethod::Inbox' && !$always_checked ) {
                $subscr->_deactivate;
            }
            else {
                $subscr->delete;
            }
        }
        else {
            $subscr->delete;
        }
    }
}

# deletes a subscription
sub delete {
    my $self = shift;
    my $u    = $self->owner;

    my @subs = $self->corresponding_subs;
    foreach my $subscr (@subs) {
        $u->do( "DELETE FROM subs WHERE subid=? AND userid=?", undef, $subscr->id, $u->id );
    }

    # delete from cache in user
    undef $u->{_subscriptions};

    return 1;
}

# class method, nukes all subs for a user
sub delete_all_subs {
    my ( $class, $u ) = @_;

    return if $u->is_expunged;
    $u->do( "DELETE FROM subs WHERE userid = ?", undef, $u->id );
    undef $u->{_subscriptions};

    return 1;
}

# class method, nukes all inactive subs for a user
sub delete_all_inactive_subs {
    my ( $class, $u, $dryrun ) = @_;

    return if $u->is_expunged;

    my @subs = $class->find($u);
    @subs = grep { !( $_->active && $_->enabled ) } @subs;
    my $count = scalar @subs;
    if ( $count > 0 && !$dryrun ) {
        $_->delete foreach (@subs);
        undef $u->{_subscriptions};
    }

    return $count;
}

# find matching subscriptions with different notification methods
sub corresponding_subs {
    my $self = shift;

    my @subs = ($self);

    if ( $self->method eq 'LJ::NotificationMethod::Inbox' ) {
        push @subs,
            $self->owner->find_subscriptions(
            journalid => $self->journalid,
            etypeid   => $self->etypeid,
            arg1      => $self->arg1,
            arg2      => $self->arg2,
            );
    }

    return @subs;
}

# Class method
sub new_from_row {
    my ( $class, $row ) = @_;

    return undef unless $row;
    my $self = bless {%$row}, $class;

    # TODO validate keys of row.
    return $self;
}

sub create {
    my ( $class, $u, %args ) = @_;

    # easier way for eveenttype
    if ( my $evt = delete $args{'event'} ) {
        $args{etypeid} = LJ::Event->event_to_etypeid($evt);
    }

    # easier way to specify ntypeid
    if ( my $ntype = delete $args{'method'} ) {
        $args{ntypeid} = LJ::NotificationMethod->method_to_ntypeid($ntype);
    }

    # easier way to specify journal
    if ( my $ju = delete $args{'journal'} ) {
        $args{journalid} = $ju->{userid} if $ju;
    }

    $args{arg1} ||= 0;
    $args{arg2} ||= 0;

    $args{journalid} ||= 0;

    foreach (qw(ntypeid etypeid)) {
        croak "Required field '$_' not found in call to $class->create" unless defined $args{$_};
    }
    foreach (qw(userid subid createtime)) {
        croak "Can't specify field '$_'" if defined $args{$_};
    }

    # load current subscription, check if subscription already exists
    $class->subscriptions_of_user($u) unless $u->{_subscriptions};
    my ($existing) = grep {
               $args{etypeid} == $_->{etypeid}
            && $args{ntypeid} == $_->{ntypeid}
            && $args{journalid} == $_->{journalid}
            && $args{arg1} == $_->{arg1}
            && $args{arg2} == $_->{arg2}
            && ( $args{flags} & DISABLED ) == $_->disabled
            && ( $args{flags} & TRACKING ) == $_->is_tracking_category
    } @{ $u->{_subscriptions} };

    # allow matches if the activation state is unequal

    if ( defined $existing ) {
        $existing->activate;
        return $existing;
    }

    my $subid = LJ::alloc_user_counter( $u, 'E' )
        or die "Could not alloc subid for user $u->{user}";

    $args{subid}      = $subid;
    $args{userid}     = $u->{userid};
    $args{createtime} = time();

    my $self = $class->new_from_row( \%args );

    my @columns;
    my @values;

    foreach (@subs_fields) {
        if ( exists( $args{$_} ) ) {
            push @columns, $_;
            push @values,  delete $args{$_};
        }
    }

    croak( "Extra args defined, (" . join( ', ', keys(%args) ) . ")" ) if keys %args;

    my $sth =
        $u->prepare( 'INSERT INTO subs ('
            . join( ',', @columns ) . ')'
            . 'VALUES ('
            . join( ',', map { '?' } @values )
            . ')' );
    $sth->execute(@values);
    LJ::errobj($u)->throw if $u->err;

    $self->subscriptions_of_user($u) unless $u->{_subscriptions};
    push @{ $u->{_subscriptions} }, $self;

    return $self;
}

# returns a hash of arguments representing this subscription (useful for passing to
# other functions, such as find)
sub sub_info {
    my $self = shift;
    return (
        journalid => $self->journalid,
        etypeid   => $self->etypeid,
        ntypeid   => $self->ntypeid,
        arg1      => $self->arg1,
        arg2      => $self->arg2,
        flags     => $self->flags,
    );
}

# returns a nice HTML description of this current subscription
sub as_html {
    my $self = shift;

    my $evtclass = LJ::Event->class( $self->etypeid );
    return undef unless $evtclass;
    return $evtclass->subscription_as_html($self);
}

sub set_tracking {
    my $self = shift;
    $self->set_flag(TRACKING);
}

sub activate {
    my $self = shift;
    $self->clear_flag(INACTIVE);
}

sub _deactivate {
    my $self = shift;
    $self->set_flag(INACTIVE);
}

sub enable {
    my $self = shift;

    $_->clear_flag(DISABLED) foreach $self->corresponding_subs;
}

sub disable {
    my $self = shift;

    $_->set_flag(DISABLED) foreach $self->corresponding_subs;
}

sub set_flag {
    my ( $self, $flag ) = @_;

    my $flags = $self->flags;

    # don't bother if flag already set
    return if $flags & $flag;

    $flags |= $flag;

    if ( $self->owner && !$self->pending ) {
        $self->owner->do( "UPDATE subs SET flags = flags | ? WHERE userid=? AND subid=?",
            undef, $flag, $self->owner->userid, $self->id );
        die $self->owner->errstr if $self->owner->errstr;

        $self->{flags} = $flags;
        delete $self->owner->{_subscriptions};
    }
}

sub clear_flag {
    my ( $self, $flag ) = @_;

    my $flags = $self->flags;

    # don't bother if flag already cleared
    return unless $flags & $flag;

    # clear the flag
    $flags &= ~$flag;

    if ( $self->owner && !$self->pending ) {
        $self->owner->do( "UPDATE subs SET flags = flags & ~? WHERE userid=? AND subid=?",
            undef, $flag, $self->owner->userid, $self->id );
        die $self->owner->errstr if $self->owner->errstr;

        $self->{flags} = $flags;
        delete $self->owner->{_subscriptions};
    }
}

sub id {
    my $self = shift;

    return $self->{subid};
}

sub createtime {
    my $self = shift;
    return $self->{createtime};
}

sub flags {
    my $self = shift;
    return $self->{flags} || 0;
}

sub active {
    my $self = shift;
    return !( $self->flags & INACTIVE );
}

sub enabled {
    my $self = shift;
    return !( $self->flags & DISABLED );
}

sub disabled {
    my $self = shift;
    return !$self->enabled;
}

sub is_tracking_category {
    my $self = shift;
    return $self->flags & TRACKING;
}

sub expiretime {
    my $self = shift;
    return $self->{expiretime};
}

sub journalid {
    my $self = shift;
    return $self->{journalid};
}

sub journal {
    my $self = shift;
    return LJ::load_userid( $self->{journalid} );
}

sub arg1 {
    my $self = shift;
    return $self->{arg1};
}

sub arg2 {
    my $self = shift;
    return $self->{arg2};
}

sub ntypeid {
    my $self = shift;
    return $self->{ntypeid};
}

sub method {
    my $self = shift;
    return LJ::NotificationMethod->class( $self->ntypeid );
}

sub notify_class {
    my $self = shift;
    return LJ::NotificationMethod->class( $self->{ntypeid} );
}

sub etypeid {
    my $self = shift;
    return $self->{etypeid};
}

sub event_class {
    my $self = shift;
    return LJ::Event->class( $self->{etypeid} );
}

# returns the owner (userid) of the subscription
sub userid {
    my $self = shift;
    return $self->{userid};
}

sub owner {
    my $self = shift;
    return LJ::load_userid( $self->{userid} );
}

sub dirty {
    my $self = shift;
    return $self->{is_dirty};
}

sub notification {
    my $subscr = shift;
    my $class  = LJ::NotificationMethod->class( $subscr->{ntypeid} );

    my $note;
    if ( $LJ::DEBUG{'official_post_esn'} && $subscr->etypeid == LJ::Event::OfficialPost->etypeid ) {

        # we had (are having) some problems with subscriptions to millions of people, so
        # this exists for now for debugging that, without actually emailing/inboxing
        # those people while we debug
        $note = LJ::NotificationMethod::DebugLog->new_from_subscription( $subscr, $class );
    }
    else {
        $note = $class->new_from_subscription($subscr);
    }

    return $note;
}

sub process {
    my ( $self, @events ) = @_;
    my $note = $self->notification or return;

    # pass along debugging information from the schwartz job
    $note->{_debug_headers} = $self->{_debug_headers} if $LJ::DEBUG{esn_email_headers};

    return 1
        if $self->etypeid == LJ::Event::OfficialPost->etypeid
        && !LJ::is_enabled('officialpost_esn');

  # significant events (such as SecurityAttributeChanged) must be processed even for inactive users.
    return 1
        unless $self->notify_class->configured_for_user( $self->owner )
        || LJ::Event->class( $self->etypeid )->is_significant;

    return $note->notify(@events);
}

sub unique {
    my $self = shift;

    my $note = $self->notification or return undef;
    return $note->unique . ':' . $self->owner->{user};
}

# returns true if two subscriptions are equivalent
sub equals {
    my ( $self, $other ) = @_;

    return 1 if defined $other->id && $self->id == $other->id;

    my $match =
           $self->ntypeid == $other->ntypeid
        && $self->etypeid == $other->etypeid
        && $self->flags == $other->flags;

    $match &&= $other->arg1 && ( $self->arg1 == $other->arg1 ) if $self->arg1;
    $match &&= $other->arg2 && ( $self->arg2 == $other->arg2 ) if $self->arg2;

    $match &&= $self->journalid == $other->journalid;

    return $match;
}

sub available_for_user {
    my ( $self, $u ) = @_;

    $u ||= $self->owner;

    return $self->event_class->available_for_user( $u, $self );
}

package LJ::Error::Subscription::TooMany;
sub fields { qw(subscr u); }

sub as_html { $_[0]->as_string }

sub as_string {
    my $self = shift;
    my $max  = $self->field('u')->count_max_subscriptions;
    return
          'The notification tracking "'
        . $self->field('subscr')->as_html
        . '" was not saved because you have'
        . " reached your limit of $max active notifications. Notifications need to be deactivated before more can be added.";
}

# Too many subscriptions exist, not necessarily active
package LJ::Error::Subscription::TooManySystemMax;
sub fields { qw(subscr u max); }

sub as_html { $_[0]->as_string }

sub as_string {
    my $self = shift;
    my $max  = $self->field('max');
    return
          'The notification tracking "'
        . $self->field('subscr')->as_html
        . '" was not saved because you have'
        . " more than $max existing notifications. Notifications need to be completely removed before more can be added.";
}

1;
