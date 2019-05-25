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

package LJ::Event;
use strict;
no warnings 'uninitialized';

use Carp qw(croak);
use LJ::ModuleLoader;
use LJ::ESN;
use LJ::Subscription;
use LJ::Typemap;

my @EVENTS = LJ::ModuleLoader->module_subclasses("LJ::Event");
foreach my $event (@EVENTS) {
    eval "use $event";
    die "Error loading event module '$event': $@" if $@;
}

# Guide to subclasses:
#    LJ::Event::JournalNewEntry    -- a journal (user/community) has a new entry in it
#                                   ($ju,$ditemid,undef)
#    LJ::Event::JournalNewComment  -- a journal has a new comment in it
#                                   ($ju,$jtalkid)   # TODO: should probably be ($ju,$jitemid,$jtalkid)
#    LJ::Event::JournalNewComment::TopLevel -- a journal has a new top-level comment in it
#                                   ($ju,$jitemid)
#    LJ::Event::JournalNewComment::Reply -- reply to your own comment/entry or reply by you
#                                   ($ju,$jtalkid)
#    LJ::Event::AddedToCircle      -- user $fromuserid added $u to their circle; $actionid is 1 (trust) or 2 (watch)
#                                   ($u,$fromuserid,$actionid)
#    LJ::Event::RemovedFromCircle  -- user $fromuserid removed $u to their circle; $actionid is 1 (trust) or 2 (watch)
#                                   ($u,$fromuserid,$actionid)
#    LJ::Event::CommunityInvite    -- user $fromuserid invited $u to join $commid community)
#                                   ($u,$fromuserid, $commid)
#    LJ::Event::InvitedFriendJoins -- user $u1 was invited to join by $u2 and created a journal
#                                   ($u1, $u2)
#    LJ::Event::NewUserpic         -- user $u uploaded userpic $up
#                                   ($u,$up)
#    LJ::Event::UserExpunged       -- user $u is expunged
#                                   ($u)
#    LJ::Event::Birthday           -- user $u's birthday
#                                   ($u)
#    LJ::Event::PollVote           -- $u1 voted in poll $p posted by $u
#                                   ($u, $u1, $up)
#    LJ::Event::UserMessageRecvd   -- user $u received message with ID $msgid from user $otherid
#                                   ($u, $msgid, $otherid)
#    LJ::Event::UserMessageSent    -- user $u sent message with ID $msgid to user $otherid
#                                   ($u, $msgid, $otherid)
#    LJ::Event::ImportStatus       -- user $u has received an import status notification
#                                   ($u, $item, $hashref)
sub new {
    my ( $class, $u, @args ) = @_;
    croak("too many args") if @args > 2;
    croak("args must be numeric") if grep { /\D/ } @args;
    croak("u isn't a user") unless LJ::isu($u);

    return bless {
        userid => $u->id,
        args   => \@args,
    }, $class;
}

sub arg_list {
    return ( "Arg 1", "Arg 2" );
}

# Class method
sub new_from_raw_params {
    my ( undef, $etypeid, $journalid, $arg1, $arg2 ) = @_;

    my $class   = LJ::Event->class($etypeid)  or die "Classname cannot be undefined/false";
    my $journal = LJ::load_userid($journalid) or die "Invalid journalid $journalid";
    my $evt = LJ::Event->new( $journal, $arg1, $arg2 );

    # bless into correct class
    bless $evt, $class;

    return $evt;
}

sub raw_params {
    my $self = shift;
    use Data::Dumper;
    my $ju = $self->event_journal
        or Carp::confess( "Event $self has no journal: " . Dumper($self) );
    my @params =
        map { $_ + 0 } ( $self->etypeid, $ju->{userid}, $self->{args}[0], $self->{args}[1] );
    return wantarray ? @params : \@params;
}

# Override this.  by default, events are rare, so subscriptions to
# them are tracked in target's "has_subscription" table.
# for common events, change this to '1' in subclasses and events
# will always fire without consulting the "has_subscription" table
sub is_common {
    0;
}

# Override this with a false value if subscriptions to this event should
# not show up in normal UI
sub is_visible { 1 }

# Override this with a true if notification to this event should be sent
# even if user account is not in active state.
sub is_significant { 0 }

# Whether Inbox is always subscribed to
sub always_checked { 0 }

# Override this with HTML containing the actual event
sub content { '' }

# Override this with HTML containing a summary of the event text (may be left blank)
sub content_summary { '' }

# Override this to provide details, method for XMLRPC::getinbox
sub raw_info {
    my $self = shift;

    my $subclass = ref $self;
    $subclass =~ s/LJ::Event:?:?//;

    return { type => $subclass };
}

sub as_string {
    my ( $self, $u ) = @_;

    croak "No target passed to Event->as_string" unless LJ::isu($u);

    my ($classname) = ( ref $self ) =~ /Event::(.+?)$/;
    return "Event $classname fired for user=$u->{user}, args=[@{$self->{args}}]";
}

# default is just return the string, override if subclass
# actually can generate pretty content
sub as_html {
    my ( $self, $u ) = @_;

    croak "No target passed to Event->as_string" unless LJ::isu($u);

    return $self->as_string;
}

# plaintext email subject
sub as_email_subject {
    my ( $self, $u ) = @_;
    return $self->as_string($u);
}

# contents for HTML email
sub as_email_html {
    my ( $self, $u ) = @_;
    return $self->as_email_string($u);
}

# contents for plaintext email
sub as_email_string {
    my ( $self, $u ) = @_;
    return $self->as_string($u);
}

# the "From" line for email
sub as_email_from_name {
    my ( $self, $u ) = @_;
    return $LJ::SITENAMESHORT;
}

# Optional headers (for comment notifications)
sub as_email_headers {
    my ( $self, $u ) = @_;
    return undef;
}

# class method, takes a subscription
sub subscription_as_html {
    my ( $class, $subscr ) = @_;

    croak "No subscription" unless $subscr;

    my $arg1      = $subscr->arg1;
    my $arg2      = $subscr->arg2;
    my $journalid = $subscr->journalid;

    my $user = $journalid ? LJ::ljuser( LJ::load_userid($journalid) ) : "(wildcard)";

    return $class . " arg1: $arg1 arg2: $arg2 user: $user";
}

# override in subclasses
sub subscription_applicable {
    my ( $class, $subscr ) = @_;

    return 1;
}

# can $u subscribe to this event?
sub available_for_user {
    my ( $class, $u, $subscr ) = @_;

    return 1;
}

# override for very hard events
sub schwartz_role { 'default' }

# Quick way to bypass during subscription lookup
sub early_filter_event {

    # arguments: ($class,$evt) = @_;
    return 1;
}

# additional SQL for subscriptions
#  does not need to be prefixed with 'AND'
sub additional_subscriptions_sql {

    # arguments: ($class,$evt) = @_;
    return ('');
}

# valid values are nothing ("" or undef), "all", or "friends"
sub zero_journalid_subs_means {

    # arguments: ($class,$evt) = @_;
    return '';
}

############################################################################
#            Don't override
############################################################################

sub event_journal { &u; }
sub u             { LJ::load_userid( $_[0]->{userid} ) }
sub arg1          { $_[0]->{args}[0] }
sub arg2          { $_[0]->{args}[1] }

# class method
sub process_fired_events {
    my $class = shift;
    croak("Can't call in web context") if LJ::is_web_context();
    LJ::ESN->process_fired_events;
}

# instance method.
# fire either logs the event to the delayed work system to be
# processed later, or does nothing, if it's a rare event and there
# are no subscriptions for the event.
sub fire {
    my $self = shift;
    return 0 unless LJ::is_enabled('esn');

    my $sclient = LJ::theschwartz( { role => $self->schwartz_role } );
    return 0 unless $sclient;

    my $job = $self->fire_job
        or return 0;

    my $h = $sclient->insert($job);
    return $h ? 1 : 0;
}

# returns the job object that would've fired, so callers can batch them together
# in one insert_jobs (plural) call.  returns empty list or single item.  doesn't
# return undef.
sub fire_job {
    my $self = shift;
    return unless LJ::is_enabled('esn');

    if ( my $val = $LJ::DEBUG{'firings'} ) {
        if ( ref $val eq "CODE" ) {
            $val->($self);
        }
        else {
            warn $self->as_string . "\n";
        }
    }

    return unless $self->should_enqueue;

    return TheSchwartz::Job->new_from_array( "LJ::Worker::FiredEvent", [ $self->raw_params ] );
}

sub subscriptions {
    my ( $self, %args ) = @_;
    my $cid_in  = delete $args{'cluster'};    # optional
    my $limit   = delete $args{'limit'};      # optional
    my $scratch = {};
    croak( "Unknown options: " . join( ', ', keys %args ) ) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    $scratch->{limit_remain} = $limit;

    my @subs;

    my @event_classes = grep { $_->early_filter_event($self) } $self->related_event_classes;

    foreach my $cid ( $cid_in ? ($cid_in) : @LJ::CLUSTERS ) {
        last if $limit && $scratch->{limit_remain} <= 0;
        foreach my $class (@event_classes) {
            last if $limit && $scratch->{limit_remain} <= 0;
            my $etypeid = $class->etypeid;
            $scratch->{"evt:$etypeid"} //= {};
            push @subs, $class->raw_subscriptions( $self, scratch => $scratch, cluster => $cid );
        }
    }

    return @subs;
}

sub raw_subscriptions {
    my ( $class, $self, %args ) = @_;
    my $cid = delete $args{'cluster'};
    croak("Cluser id (cluster) must be provided") unless defined $cid;

    my $scratch = delete $args{'scratch'} || {};    # optional

    croak( "Unknown options: " . join( ', ', keys %args ) ) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    # allsubs
    my @subs;

    my $etypeid     = $class->etypeid;
    my $evt_scratch = $scratch->{"evt:$etypeid"} // {};

    my $limit_remain = $scratch->{limit_remain};
    my $and_enabled =
        "AND flags & " . ( LJ::Subscription->INACTIVE | LJ::Subscription->DISABLED ) . " = 0";

    return if defined $limit_remain && $limit_remain <= 0;

    my $allmatch = 0;
    my $zeromeans;
    my ( $addl_sql, @addl_args );
    my @wildcards_from;

    if ( defined $evt_scratch->{allmatch} ) {
        $zeromeans      = $evt_scratch->{zeromeans};
        $allmatch       = $evt_scratch->{allmatch};
        @wildcards_from = @{ $evt_scratch->{wildcards_from} };
        $addl_sql       = $evt_scratch->{addl_sql};
        @addl_args      = @{ $evt_scratch->{addl_args} };
    }
    else {
        $zeromeans = $class->zero_journalid_subs_means($self);

        ( $addl_sql, @addl_args ) = $class->additional_subscriptions_sql($self);
        $addl_sql = " AND ( $addl_sql )" if $addl_sql;

        if ( $zeromeans eq 'trusted' ) {
            @wildcards_from = $self->u->trusted_by_userids;
        }
        elsif ( $zeromeans eq 'watched' ) {
            @wildcards_from = $self->u->watched_by_userids;
        }
        elsif ( $zeromeans eq 'trusted_or_watched' ) {
            my %unique_ids =
                map { $_ => 1 } ( $self->u->trusted_by_userids, $self->u->watched_by_userids );
            @wildcards_from = keys %unique_ids;
        }
        elsif ( $zeromeans eq 'all' ) {
            $allmatch = 1;
        }

        $evt_scratch->{zeromeans}      = $zeromeans;
        $evt_scratch->{allmatch}       = $allmatch;
        $evt_scratch->{wildcards_from} = \@wildcards_from;
        $evt_scratch->{addl_sql}       = $addl_sql;
        $evt_scratch->{addl_args}      = \@addl_args;
    }

    my $dbcm = LJ::get_cluster_master($cid)
        or die;

    # first we find exact matches (or all matches)
    my $journal_match = $allmatch ? "" : "AND journalid=?";
    my $limit_sql = $limit_remain ? "LIMIT $limit_remain" : '';
    my $sql =
          "SELECT userid, subid, is_dirty, journalid, etypeid, "
        . "arg1, arg2, ntypeid, createtime, expiretime, flags  "
        . "FROM subs WHERE etypeid = ? $journal_match $and_enabled $addl_sql $limit_sql";

    my $sth  = $dbcm->prepare($sql);
    my @args = ($etypeid);
    push @args, $self->u->id unless $allmatch;
    $sth->execute( @args, @addl_args );
    if ( $sth->err ) {
        warn "SQL: [$sql], args=[@args], addl_args=[@addl_args]\n";
        die $sth->errstr;
    }

    while ( my $row = $sth->fetchrow_hashref ) {
        push @subs, LJ::Subscription->new_from_row($row);
    }

    # then we find wildcard matches.
    if (@wildcards_from) {

        # FIXME: journals are only on one cluster! split jidlist based on cluster
        my $jidlist = join( ",", @wildcards_from );

        my $sth =
            $dbcm->prepare( "SELECT userid, subid, is_dirty, journalid, etypeid, "
                . "arg1, arg2, ntypeid, createtime, expiretime, flags  "
                . "FROM subs USE INDEX(PRIMARY) WHERE etypeid = ? AND journalid=0 $and_enabled AND userid IN ($jidlist) $addl_sql"
            );

        $sth->execute( $etypeid, @addl_args );
        die $sth->errstr if $sth->err;

        while ( my $row = $sth->fetchrow_hashref ) {
            push @subs, LJ::Subscription->new_from_row($row);
        }
    }

    $limit_remain -= @subs;

    $scratch->{limit_remain} = $limit_remain
        if defined $scratch->{limit_remain};

    return @subs;
}

# helper method to be called when overriding parent's raw_subscriptions
# method to always return a subscription object for the user
sub _raw_always_subscribed {
    my ( $class, $self, %args ) = @_;
    my $cid = delete $args{'cluster'};
    croak("Cluser id (cluster) must be provided") unless defined $cid;

    my $scratch = delete $args{'scratch'};    # optional

    # hash keys specific to this helper method
    my $skip_parent = delete $args{'skip_parent'};    # optional
    my $ntypeid     = delete $args{'ntypeid'};
    croak("Failed to provide ntypeid") unless defined $ntypeid;

    croak( "Unknown options: " . join( ', ', keys %args ) ) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @subs;
    my $u = $self->u;
    return unless $cid == $u->clusterid;

    my $row = {
        userid  => $self->u->id,
        ntypeid => $ntypeid,
        etypeid => $class->etypeid,
    };

    push @subs, LJ::Subscription->new_from_row($row);

    push @subs,
        eval { LJ::Event::raw_subscriptions( $class, $self, cluster => $cid, scratch => $scratch ) }
        unless $skip_parent;

    return @subs;
}

# INSTANCE METHOD: SHOULD OVERRIDE if the subscriptions support filtering
sub matches_filter {
    my ( $self, $subsc ) = @_;

    return 0 unless $subsc->available_for_user;
    return 1;
}

# instance method. Override if possible.
# returns when the event happened, or undef if unknown
sub eventtime_unix {
    return undef;
}

# instance method
sub should_enqueue {
    my $self = shift;
    return 1;    # for now.
    return $self->is_common || $self->has_subscriptions;
}

# instance method
# Override this to have notifications for an event show up as read
sub mark_read {
    my $self = shift;
    return 0;
}

# instance method
sub has_subscriptions {
    my $self = shift;
    return 1;    # FIXME: consult "has_subs" table
}

sub get_subscriptions {
    my ( $self, $u, $subid ) = @_;

    return LJ::Subscription->new_by_id( $u, $subid );
}

# get the typemap for the subscriptions classes (class/instance method)
sub typemap {
    return LJ::Typemap->new(
        table      => 'eventtypelist',
        classfield => 'class',
        idfield    => 'etypeid',
    );
}

# returns the class name, given an etypid
sub class {
    my ( $class, $typeid ) = @_;
    my $tm = $class->typemap
        or return undef;

    $typeid ||= $class->etypeid;

    return $tm->typeid_to_class($typeid);
}

# returns the eventtypeid for this site.
# don't override this in subclasses.
sub etypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    my $tm = $class->typemap
        or return undef;

    return $tm->class_to_typeid($class);
}

# return a list of related events, for considering as one group
# to avoid dupes when processing subs
# list includes your own etypeid
sub related_event_classes {
    return $_[0];
}

sub related_events {
    return return map { $_->etypeid } $_[0]->related_event_classes;
}

# Class method
sub event_to_etypeid {
    my ( $class, $evt_name ) = @_;
    $evt_name = "LJ::Event::$evt_name" unless $evt_name =~ /^LJ::Event::/;
    my $tm = $class->typemap
        or return undef;
    return $tm->class_to_typeid($evt_name);
}

# this returns a list of all possible event classes
# class method
sub all_classes {
    my $class = shift;

    # return config'd classes if they exist, otherwise just return everything that has a mapping
    return @LJ::EVENT_TYPES if @LJ::EVENT_TYPES;

    croak "all_classes is a class method" unless $class;

    my $tm = $class->typemap
        or croak "Bad class $class";

    return $tm->all_classes;
}

sub format_options {
    my ( $self, $is_html, $lang, $vars, $urls, $extra ) = @_;

    my ( $tag_p, $tag_np, $tag_li, $tag_nli, $tag_ul, $tag_nul, $tag_br ) =
        ( '', '', '', '', '', '', "\n" );

    if ($is_html) {
        $tag_p   = '<p>';
        $tag_np  = '</p>';
        $tag_li  = '<li>';
        $tag_nli = '</li>';
        $tag_ul  = '<ul>';
        $tag_nul = '</ul>';
    }

    my $options = $tag_br . $tag_br . $tag_ul;

    if ($is_html) {
        $vars->{'closelink'} = '</a>';
        $options .= join(
            '',
            map {
                my $key = $_;
                $vars->{'openlink'} = '<a href="' . $urls->{$key}->[1] . '">';
                $tag_li . LJ::Lang::get_text( $lang, $key, undef, $vars ) . $tag_nli;
                }
                sort { $urls->{$a}->[0] <=> $urls->{$b}->[0] }
                grep { $urls->{$_}->[0] }
                keys %$urls
        );
    }
    else {
        $vars->{'openlink'}  = '';
        $vars->{'closelink'} = '';
        $options .= join(
            '',
            map {
                my $key = $_;
                '  - '
                    . LJ::Lang::get_text( $lang, $key, undef, $vars ) . ":\n" . '    '
                    . $urls->{$key}->[1] . "\n"
                }
                sort { $urls->{$a}->[0] <=> $urls->{$b}->[0] }
                grep { $urls->{$_}->[0] }
                keys %$urls
        );
        chomp($options);
    }

    $options .= $extra if $extra;

    $options .= $tag_nul . $tag_br;

    return $options;
}

1;
