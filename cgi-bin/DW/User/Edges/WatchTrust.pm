#!/usr/bin/perl
#
# DW::User::Edges::WatchTrust
#
# Implements the watch and trust edges between accounts.  These are closely
# related edges that serve a lot of core functionality of the site.  Without
# these edges, the site will probably not work.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2008 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::User::Edges::WatchTrust;
use strict;

use Carp qw/ confess /;
use DW::User::Edges::WatchTrust::Loader;
use DW::User::Edges::WatchTrust::UserHelper;

# the watch edge simply adds one user's content to another user's watch page
# and has no security implications whatsoever
DW::User::Edges::define_edge(
        watch =>
            {
                type => 'hashref',
                db_edge => 'W',
                options => {
                    fgcolor  => { required => 0, type => 'int',  default => 0        },
                    bgcolor  => { required => 0, type => 'int',  default => 16777215 },
                    nonotify => { required => 0, type => 'bool', default => 0        },
                },
                add_sub => \&_add_wt_edge,
                del_sub => \&_del_wt_edge,
            }
    );

# the trust edge is what provides authorization for one user to see another
# user's protected posts
DW::User::Edges::define_edge(
        trust =>
            {
                type => 'hashref',
                db_edge => 'T',
                options => {
                    mask     => { required => 0, type => 'int', default => 0 },
                    nonotify => { required => 0, type => 'bool', default => 0 },
                },
                add_sub => \&_add_wt_edge,
                del_sub => \&_del_wt_edge,
            }
    );

# internal method used to add a watch/trust edge to an account
sub _add_wt_edge {
    my ( $from_u, $to_u, $edges ) = @_;

    # bail unless there are watch/trust edges
    my ( $trust_edge, $watch_edge ) = ( delete $edges->{trust}, delete $edges->{watch} );
    return unless $trust_edge || $watch_edge;

    # now setup some helper variables
    my $do_watch = $watch_edge ? 1 : 0;
    $watch_edge ||= {};
    my $do_trust = $trust_edge ? 1 : 0;
    $trust_edge ||= {};

    # setup the mask, note that it has to be 0 unless the user is trusted,
    # in which case it is the trust mask with the low bit always on.  also,
    # bit #61 is on if the user is watched.
    my $mask = $do_watch ? ( 1 << 61 ) : 0;
    if ( $do_trust ) {
        $mask |= ( $trust_edge->{mask}+0 ) | 1;
    }

    # get current record, so we know what to modify
    my $dbh = LJ::get_db_writer();
    my $row = $dbh->selectrow_hashref( 'SELECT fgcolor, bgcolor, groupmask FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
                                       undef, $from_u->id, $to_u->id );
    confess $dbh->errstr if $dbh->err;
    $row ||= { groupmask => 0 };

    # only matters in the read case, but ...
    my ( $fgcol, $bgcol ) = ( $row->{fgcolor} || LJ::color_todb( '#000000' ),
                              exists $row->{bgcolor} ? $row->{bgcolor} : LJ::color_todb( '#ffffff' ) );
    $fgcol = $watch_edge->{fgcolor} if exists $watch_edge->{fgcolor};
    $bgcol = $watch_edge->{bgcolor} if exists $watch_edge->{bgcolor};

    # set extra bits to keep what the user has already set
    if ( $do_watch && $do_trust ) {
        # do nothing, assume we're overriding
    } elsif ( $do_watch ) {
        # import the trust values
        $mask |= ( $row->{groupmask} ^ ( 8 << 61 ) );
    } elsif ( $do_trust ) {
        # import the watch values
        $mask |= ( $row->{groupmask} & ( 1 << 61 ) );
    }

    # now add the row
    $dbh->do( 'REPLACE INTO wt_edges (from_userid, to_userid, fgcolor, bgcolor, groupmask) VALUES (?, ?, ?, ?, ?)',
              undef, $from_u->id, $to_u->id, $fgcol, $bgcol, $mask );
    confess $dbh->errstr if $dbh->err;

    # delete friend-of memcache keys for anyone who was added
    my ( $from_userid, $to_userid ) = ( $from_u->id, $to_u->id );
    LJ::MemCache::delete( [$from_userid, "trustmask:$from_userid:$to_userid"] );
    LJ::memcache_kill( $to_userid, 'wt_edges_rev' );
    LJ::memcache_kill( $from_userid, 'wt_edges' );
    LJ::memcache_kill( $from_userid, 'watch_list' );
    LJ::memcache_kill( $from_userid, 'watched' );
    LJ::memcache_kill( $from_userid, 'trusted' );
    LJ::memcache_kill( $to_userid, 'watched_by' );
    LJ::memcache_kill( $to_userid, 'trusted_by' );

    # fire notifications if we have theschwartz
    if ( my $sclient = LJ::theschwartz() ) {

        # part of the criteria for whether to fire befriended event
        my $skip_notify = ( $trust_edge->{nonotify} || $watch_edge->{nonotify} ) ? 1 : 0;
        my $notify = !$LJ::DISABLED{esn} && !$skip_notify
                     && $from_u->is_visible && $from_u->is_person;

        # only fire event if the from_u is a person and not banned
        if ( $notify && ! $to_u->is_banned( $from_u ) ) {
# FIXME(mark): need a new event here instead of just Befriended
#            $sclient->insert_jobs( LJ::Event::Befriended->new( $to_u, $from_u )->fire_job );
        }
    }

    return 1;
}

# internal method to delete an edge
#
# FIXME: we should be able to accept an options here that says
# 'please do not notify', skips theschwartz event ...
#
sub _del_wt_edge {
    my ( $from_u, $to_u, $edges ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    # determine if we're doing an update or a delete
    my $de_watch = delete $edges->{watch};
    my $de_trust = delete $edges->{trust};
    return 1 unless $de_watch || $de_trust;

    # get what we know
    my $does_watch = $from_u->watches( $to_u );
    my $does_trust = $from_u->trusts( $to_u );
    return 1 unless $does_watch || $does_trust;

    # make sure we have a valid edge to remove
    return 1 unless
        ( $de_watch && $does_watch ) ||
        ( $de_trust && $does_trust );

    my $dbh = LJ::get_db_writer()
        or return 0;

    # deletes are easy, these are cases where we're removing both edges,
    # or removing the only remaining edge
    if ( ( $de_watch && $de_trust ) ||
         ( $de_watch && $does_watch && ! $does_trust ) ||
         ( $de_trust && $does_trust && ! $does_watch ) ) {

        $dbh->do( 'DELETE FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
                  undef, $from_u->id, $to_u->id );
        return 0 if $dbh->err;

    # at this point, we're guaranteed to have only the other edge remaining
    } else {

        my $mask = $de_trust ? 1 << 61 : $from_u->trustmask( $to_u );

        $dbh->do( 'UPDATE wt_edges SET groupmask = ? WHERE from_userid = ? AND to_userid = ?',
                  undef, $mask, $from_u->id, $to_u->id );
        return 0 if $dbh->err;
    }

    # kill memcaches
    LJ::memcache_kill( $from_u, 'wt_edges' );
    LJ::memcache_kill( $to_u, 'wt_edges_rev' );
    LJ::memcache_kill( $from_u, 'watch_list' );
    LJ::memcache_kill( $from_u, 'watched' );
    LJ::memcache_kill( $from_u, 'trusted' );
    LJ::memcache_kill( $to_u, 'watched_by' );
    LJ::memcache_kill( $to_u, 'trusted_by' );
    LJ::MemCache::delete( [$from_u->id, "trustmask:" . $from_u->id . ":" . $to_u->id] );

# TODO(mark): need to add this when we get the events sorted
#    # part of the criteria for whether to fire defriended event
#    my $notify = !$LJ::DISABLED{esn} && !$opts->{nonotify} && $u->is_visible && $u->is_person;
#
#    # delete friend-of memcache keys for anyone who was removed
#    foreach my $fid (@del_ids) {
#
#        my $friendee = LJ::load_userid($fid);
#        if ($sclient) {
#            my @jobs;
#
#            # only fire event if the friender is a person and not banned and visible
#            if ($notify && !$friendee->has_banned($u)) {
#                push @jobs, LJ::Event::Defriended->new($friendee, $u)->fire_job;
#            }
#            $sclient->insert_jobs(@jobs);
#        }
#    }
}

###############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
###############################################################################

# push methods up into the DW::User namespace
package DW::User;
use strict;

use Carp qw/ confess /;


# returns 1 if the given user watches the given account
# returns 0 otherwise
sub watches {
    my ( $from_u, $to_u ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    # now get the mask; note we have to use the internal method so we
    # can get the real mask - without the top-bit masking that $u->trustmask
    # does...
    my $mask = DW::User::Edges::WatchTrust::Loader::_trustmask( $from_u->id, $to_u->id );
    return ( $mask & ( 1 << 61 ) ) ? 1 : 0;
}
*LJ::User::watches = \&watches;


# returns 1 if you generally trust the target user
# returns 0 otherwise
sub trusts {
    my ( $from_u, $to_u ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    # you always trust yourself...
    return 1 if $from_u->id == $to_u->id;

    # now get the mask; again with the internal mask method
    my $mask = DW::User::Edges::WatchTrust::Loader::_trustmask( $from_u->id, $to_u->id );
    return ( $mask & 1 ) ? 1 : 0;
}
*LJ::User::trusts = \&trusts;


# return 1/0 if the given user is mutually trusted
sub mutually_trusts {
    my ( $from_u, $to_u ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    return 1 if $from_u->trusts( $to_u ) &&
                $to_u->trusts( $from_u );
    return 0;
}
*LJ::User::mutually_trusts = \&mutually_trusts;


# returns URL of watchwatch page
sub watchwatch_url {
    my $u = LJ::want_user( $_[0] )
        or confess 'invalid user object';
    return $u->journal_base . '/watchwatch';
}


# returns URL of trust management page
sub manage_trust_url {
    my $u = LJ::want_user( $_[0] )
        or confess 'invalid user object';
    return "$LJ::SITEROOT/manage/trust.bml?user=$u->{user}";
}
*LJ::User::manage_trust_url = \&manage_trust_url;


# returns a numeric trustmask
sub trustmask {
    my ( $from_u, $to_u ) = @_;
    my $from_userid = LJ::want_userid( $from_u ) or return 0;
    my $to_userid = LJ::want_userid( $to_u ) or return 0;

    # note: we mask out the top three bits (i.e., the reserved bits and the watch bit)
    # so external callers never see them.
    return DW::User::Edges::WatchTrust::Loader::_trustmask( $from_userid, $to_userid ) ^ ( 8 << 61 );
}
*LJ::User::trustmask = \&trustmask;


# name: LJ::User::get_birthdays
# des: get the upcoming birthdays for friends of a user. shows birthdays 3 months away by default
#      pass in full => 1 to get all friends' birthdays.
# returns: arrayref of [ month, day, user ] arrayrefs
sub get_birthdays {

    confess 'get_birthdays not updated yet';

    my $u = LJ::want_user( shift )
        or return undef;

    my %opts = @_;
    my $months_ahead = $opts{months_ahead} || 3;
    my $full = $opts{full};

    # what day is it now?
    my $now = $u->time_now;
    my ($mnow, $dnow) = ($now->month, $now->day);

    my $bday_sort = sub {
        # first we sort them normally...
        my @bdays = sort {
            ($a->[0] <=> $b->[0]) || # month sort
            ($a->[1] <=> $b->[1])    # day sort
        } @_;

        # fast path out if we're getting all birthdays.
        return @bdays if $full;

        # then we need to push some stuff to the end. consider "three months ahead"
        # from november ... we'd get data from january, which would appear at the
        # head of the list.
        my $nowstr = sprintf("%02d-%02d", $mnow, $dnow);
        my $i = 0;
        while ($i++ < @bdays && sprintf("%02d-%02d", @{ $bdays[0] }) lt $nowstr) {
            push @bdays, shift @bdays;
        }

        return @bdays;
    };

    my $memkey = [$u->userid, 'bdays:' . $u->userid . ':' . ($full ? 'full' : $months_ahead)];
    my $cached_bdays = LJ::MemCache::get($memkey);
    return $bday_sort->(@$cached_bdays) if $cached_bdays;

    my @friends = $u->friends;
    my @bdays;

    foreach my $friend (@friends) {
        my ($year, $month, $day) = split('-', $friend->{bdate});
        next unless $month > 0 && $day > 0;

        # skip over unless a few months away (except in full mode)
        unless ($full) {
            # the case where months_ahead doesn't wrap around to a new year
            if ($mnow + $months_ahead <= 12) {
                # discard old months
                next if $month < $mnow;
                # discard months too far in the future
                next if $month > $mnow + $months_ahead;

            # the case where we wrap around the end of the year (eg, oct->jan)
            } else {
                # we're okay if the month is in the future, because
                # we KNOW we're wrapping around. but if the month is
                # in the past, we need to verify that we've wrapped
                # around and are still within the timeframe
                next if ($month < $mnow) && ($month > ($mnow + $months_ahead) % 12);
            }

            # month is fine. check the day.
            next if ($month == $mnow && $day < $dnow);
        }

        if ($friend->can_show_bday) {
            push @bdays, [ $month, $day, $friend->user ];
        }
    }

    # set birthdays in memcache for later
    LJ::MemCache::set($memkey, \@bdays, 86400);

    return $bday_sort->(@bdays);
}
*LJ::User::get_birthdays = \&get_birthdays;


# return users you trust
sub trusted_users {
    my $u = shift;
    my @trustids = $u->trusted_userids;
    my $users = LJ::load_userids(@trustids);
    return values %$users if wantarray;
    return $users;
}
*LJ::User::trusted_users = \&trusted_users;


# returns array of trusted by uids.  by default, limited at 50,000 items.
sub trusted_by_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'not a valid user object';
    my $limit = int(delete $args{limit}) || 50000;
    confess 'unknown option' if %args;

    return DW::User::Edges::WatchTrust::Loader::_wt_userids(
            $u, limit => $limit, mode => 'trust', reverse => 1
        );
}
*LJ::User::trusted_by_userids = \&trusted_by_userids;


# returns array of trusted uids.  by default, limited at 50,000 items.
sub trusted_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'not a valid user object';
    my $limit = int(delete $args{limit}) || 50000;
    confess 'unknown option' if %args;

    return DW::User::Edges::WatchTrust::Loader::_wt_userids(
            $u, limit => $limit, mode => 'trust'
        );
}
*LJ::User::trusted_userids = \&trusted_userids;


# returns array of watched by uids.  by default, limited at 50,000 items.
sub watched_by_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'not a valid user object';
    my $limit = int(delete $args{limit}) || 50000;
    confess 'unknown option' if %args;

    return DW::User::Edges::WatchTrust::Loader::_wt_userids(
            $u, limit => $limit, mode => 'watch', reverse => 1
        );
}
*LJ::User::watched_by_userids = \&watched_by_userids;


# returns array of watched uids.  by default, limited at 50,000 items.
sub watched_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'not a valid user object';
    my $limit = int(delete $args{limit}) || 50000;
    confess 'unknown option' if %args;

    return DW::User::Edges::WatchTrust::Loader::_wt_userids(
            $u, limit => $limit, mode => 'watch'
        );
}
*LJ::User::watched_userids = \&watched_userids;


# returns hashref;
#
#   { userid =>
#      { groupmask => NNN, fgcolor => '#xxx', bgcolor => '#xxx', showbydefault => NNN }
#   }
#
# one entry in the hashref for everything the given user is watching.
#
# arguments is a hash of options
#    memcache_only => 1,     if set, never hit database
#    force_database => 1,    if set, ALWAYS hit database (DANGER)
#
sub watch_list {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    my $memc_only = delete $args{memcache_only} || 0;
    my $db_only = delete $args{force_database} || 0;
    confess 'extra/invalid arguments' if %args;

    # special case, we can disable loading friends for a user if there is a site
    # problem or some other issue with this codebranch
    return undef if $LJ::FORCE_EMPTY_FRIENDS{ $u->id };

    # attempt memcache if allowed
    unless ( $db_only ) {
        my $memc = DW::User::Edges::WatchTrust::Loader::_watch_list_memc( $u );
        return $memc if $memc;
    }

    # bail early if we are supposed to only hit memcache, this saves us from a
    # potentially expensive database call in codepaths that are best-effort
    return {} if $memc_only;

    # damn you memcache for not having our data
    return DW::User::Edges::WatchTrust::Loader::_watch_list_db( $u );
}
*LJ::User::watch_list = \&watch_list;


# gets a hashref of trust group requested.  arguments is a hash of options
#   bit => NNN,     bit of group to get
#   name => "ZZZ",  name of group to get
#
# returns undef if group not found
#
sub trust_groups {
    my ( $u, %opts ) = @_;
    my $u = LJ::want_user( $u )
        or confess 'invalid user object';
    my $bit = delete( $opts{bit} )+0;
    confess 'invalid bit number' if $bit < 0 || $bit > 60;
    my $name = lc delete( $opts{name} );
    confess 'invalid arguments' if %opts;

    return DW::User::Edges::WatchTrust::Loader::_trust_groups( $u, $bit, $name );
}
*LJ::User::trust_groups = \&trust_groups;


# TODO(mark): update the following subs

# Returns a list of friends who are actual people, not communities or feeds
#sub people_friends {
#    return grep { $_->is_person || $_->is_identity } $_[0]->friends;
#}

# the count of friends that the user has added
# -- eg, not initial friends auto-added for them
#sub friends_added_count {
#    my $u = shift;
#
#    my %initial = ( map { $_ => 1 } @LJ::INITIAL_FRIENDS, @LJ::INITIAL_OPTIONAL_FRIENDS, $u->user );
#
#    # return count of friends who were not initial
#    return scalar grep { ! $initial{$_->user} } $u->friends;
#}







# internal helper sub to determine if we're at the rate limit
sub _can_add_wt_edge {
    my ($u, $err, $opts) = @_;

    if ($u->is_suspended) {
        $$err = "Suspended journals cannot add friends.";
        return 0;
    }

    # have they reached their friend limit?
    my $fr_count = $opts->{'numfriends'} || $u->friend_uids;
    my $maxfriends = $u->get_cap('maxfriends');
    if ($fr_count >= $maxfriends) {
        $$err = "You have reached your limit of $maxfriends friends.";
        return 0;
    }

    # are they trying to add friends too quickly?

    # don't count mutual friends
    if (exists($opts->{friend})) {
        my $fr_user = $opts->{friend};
        # we needed LJ::User object, not just a hash.
        if (ref($fr_user) eq 'HASH') {
            $fr_user = LJ::load_user($fr_user->{username});
        } else {
            $fr_user = LJ::want_user($fr_user);
        }

        return 1 if $fr_user && $fr_user->is_friend($u);
    }

    unless ($u->rate_log('addfriend', 1)) {
        $$err = "You are trying to add too many friends in too short a period of time.";
        return 0;
    }

    return 1;
}


1;
