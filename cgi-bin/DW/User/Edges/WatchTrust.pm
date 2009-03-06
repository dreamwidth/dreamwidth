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
                    fgcolor  => { required => 0, type => 'int'                },
                    bgcolor  => { required => 0, type => 'int'                },
                    nonotify => { required => 0, type => 'bool', default => 0 },
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
                    mask     => { required => 0, type => 'int'                },
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

    # throw errors if we're not allowed
    return 0 if $do_watch && ! $from_u->can_watch( $to_u );
    return 0 if $do_trust && ! $from_u->can_trust( $to_u );

    # get current record, so we know what to modify
    my $dbh = LJ::get_db_writer();
    my $row = $dbh->selectrow_hashref( 'SELECT fgcolor, bgcolor, groupmask FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
                                       undef, $from_u->id, $to_u->id );
    confess $dbh->errstr if $dbh->err;
    $row ||= { groupmask => 0 };

    # store some existing trust/watch values for use later
    my $existing_watch = $row->{groupmask} &  ( 1 << 61 );
    my $existing_trust = $row->{groupmask} & ~( 7 << 61 );

    # only matters in the read case, but ...
    my ( $fgcol, $bgcol ) = ( $row->{fgcolor} || LJ::color_todb( '#000000' ),
                              exists $row->{bgcolor} ? $row->{bgcolor} : LJ::color_todb( '#ffffff' ) );
    $fgcol = $watch_edge->{fgcolor} if exists $watch_edge->{fgcolor};
    $bgcol = $watch_edge->{bgcolor} if exists $watch_edge->{bgcolor};

    # calculate the mask we're going to apply to the user; this is somewhat complicated
    # as we have to account for situations where we're updating only one of the edges, as
    # well as the situation where we are just updating the trust edge without changing
    # the user's group memberships.  lots of comments.  start with a mask of 0.
    my $mask = 0;

    # if they are adding a watch edge, simply turn that bit on
    $mask |= ( 1 << 61 ) if $do_watch;

    # if they are not adding a watch edge, import the existing watch edge
    $mask |= $existing_watch unless $do_watch;

    # if they are adding a trust edge, we need to turn bit 1 on
    $mask |= 1 if $do_trust;

    # now, we have to copy some trustmask, depending on some factors
    if ( ( $do_watch && ! $do_trust ) ||                   # 1) if we're only updating watch
         ( $do_trust && ! exists $trust_edge->{mask} ) )   # 2) they're adding a trust edge but don't set a mask
    {
        # in these two cases, we want to copy up the trustmask from the database
        $mask |= $existing_trust;
    }

    # the final case, they are trusting and have specified a mask; but note we cannot allow
    # them to set the high bits
    if ( $do_trust && exists $trust_edge->{mask} ) {
        $mask |= ( $trust_edge->{mask}+0 & ~( 7 << 61 ) );
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
    LJ::memcache_kill( $from_userid, 'wt_list' );
    LJ::memcache_kill( $from_userid, 'watched' );
    LJ::memcache_kill( $from_userid, 'trusted' );
    LJ::memcache_kill( $to_userid, 'watched_by' );
    LJ::memcache_kill( $to_userid, 'trusted_by' );

    # fire notifications if we have theschwartz
    if ( my $sclient = LJ::theschwartz() ) {
        my $notify = !$LJ::DISABLED{esn} &&
            !$from_u->equals( $to_u ) &&
            $from_u->is_visible &&
            ( $from_u->is_personal || $from_u->is_identity ) &&
            ( $to_u->is_personal || $to_u->is_identity ) &&
            !$to_u->has_banned( $from_u ) ? 1 : 0;
        my $trust_notify = $notify && !$trust_edge->{nonotify} ? 1 : 0;
        my $watch_notify = $notify && !$watch_edge->{nonotify} ? 1 : 0;

        $sclient->insert_jobs( LJ::Event::AddedToCircle->new( $to_u, $from_u, 1 )->fire_job )
            if $do_trust && $trust_notify;
        $sclient->insert_jobs( LJ::Event::AddedToCircle->new( $to_u, $from_u, 2 )->fire_job )
            if $do_watch && $watch_notify;
    }

    return 1;
}


# internal method to delete an edge
sub _del_wt_edge {
    my ( $from_u, $to_u, $edges ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    # determine if we're doing an update or a delete
    my $de_watch = delete $edges->{watch};
    my $de_trust = delete $edges->{trust};
    return 1 unless $de_watch || $de_trust;

    # now setup some helper variables
    my $do_watch = $de_watch ? 1 : 0;
    my $do_trust = $de_trust ? 1 : 0;

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
    LJ::memcache_kill( $from_u, 'wt_list' );
    LJ::memcache_kill( $from_u, 'watched' );
    LJ::memcache_kill( $from_u, 'trusted' );
    LJ::memcache_kill( $to_u, 'watched_by' );
    LJ::memcache_kill( $to_u, 'trusted_by' );
    LJ::MemCache::delete( [$from_u->id, "trustmask:" . $from_u->id . ":" . $to_u->id] );

    # fire notifications if we have theschwartz
    if ( my $sclient = LJ::theschwartz() ) {
        my $notify = !$LJ::DISABLED{esn} &&
            !$from_u->equals( $to_u ) &&
            $from_u->is_visible &&
            ( $from_u->is_personal || $from_u->is_identity ) &&
            ( $to_u->is_personal || $to_u->is_identity ) &&
            !$to_u->has_banned( $from_u ) ? 1 : 0;
        my $trust_notify = $notify && !$de_trust->{nonotify} ? 1 : 0;
        my $watch_notify = $notify && !$de_watch->{nonotify} ? 1 : 0;

        $sclient->insert_jobs( LJ::Event::RemovedFromCircle->new( $to_u, $from_u, 1 )->fire_job )
            if $do_trust && $trust_notify;
        $sclient->insert_jobs( LJ::Event::RemovedFromCircle->new( $to_u, $from_u, 2 )->fire_job )
            if $do_watch && $watch_notify;
    }
}


# returns the valid version of a group name
sub valid_group_name {
    my $name = shift;

    # strip off trailing slash(es)
    $name =~ s!/+$!!;

    # conform to maxes
    $name = LJ::text_trim( $name, LJ::BMAX_GRPNAME2, LJ::CMAX_GRPNAME2 );

    return $name;
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


# returns a numeric trustmask; can also be used as a setter if you specify a numeric
# as the third argument.  in which case it returns the newly updated trustmask.
sub trustmask {
    my ( $from_u, $to_u ) = @_;
    my $from_u = LJ::want_user( $from_u ) or return 0;
    my $to_u = LJ::want_user( $to_u ) or return 0;

    # if we still have an argument, we need to set someone's mask
    if ( scalar( @_ ) == 3 ) {
        # make sure we trust them... we have to do this here because otherwise we could
        # implicitly create a trust relationship when one doesn't exist
        confess 'attempted to set trustmask on non-trusted edge'
            unless $from_u->trusts( $to_u );

        # we update the mask by re-adding the trust edge; this is the simplest way
        # that ensures we do everything "properly"
        $from_u->add_edge( $to_u, trust => { mask => $_[2], nonotify => 1 } );
    }

    # note: we mask out the top three bits (i.e., the reserved bits and the watch bit)
    # so external callers never see them.
    return DW::User::Edges::WatchTrust::Loader::_trustmask( $from_u->id, $to_u->id ) & ~( 7 << 61 );
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


# returns array of mutually watched userids.  by default, limit at 50k.
# note that this function will be wildly inaccurate in any situation where
# an account actually has more than 50k of either direction.  but we'll
# cross that bridge when we come to it...
sub mutually_watched_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'not a valid user object';

    my %mutual;
    my %watched_fwd = map { $_ => 1 } $u->watched_userids( %args );
    foreach my $uid ( $u->watched_by_userids( %args ) ) {
        $mutual{$uid} = 1
            if exists $watched_fwd{$uid};
    }

    return keys %mutual;
}
*LJ::User::mutually_watched_userids = \&mutually_watched_userids;


# returns array of mutually trusted userids.  by default, limit at 50k.
# same limitations as above.
sub mutually_trusted_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'not a valid user object';

    my %mutual;
    my %trusted_fwd = map { $_ => 1 } $u->trusted_userids( %args );
    foreach my $uid ( $u->trusted_by_userids( %args ) ) {
        $mutual{$uid} = 1
            if exists $trusted_fwd{$uid};
    }

    return keys %mutual;
}
*LJ::User::mutually_trusted_userids = \&mutually_trusted_userids;


# returns hashref;
#
#   { userid =>
#      { groupmask => NNN, fgcolor => '#xxx', bgcolor => '#xxx', showbydefault => NNN }
#   }
#
# one entry in the hashref for everything the given user trusts.  note that fgcolor/bgcolor
# are only really useful for watched users, so these will be default/empty if the user
# is only trusted.
#
# arguments is a hash of options
#    memcache_only => 1,     if set, never hit database
#    force_database => 1,    if set, ALWAYS hit database (DANGER)
#
sub trust_list {
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
        my $memc = DW::User::Edges::WatchTrust::Loader::_trust_list_memc( $u );
        return $memc if $memc;
    }

    # bail early if we are supposed to only hit memcache, this saves us from a
    # potentially expensive database call in codepaths that are best-effort
    return {} if $memc_only;

    # damn you memcache for not having our data
    return DW::User::Edges::WatchTrust::Loader::_trust_list_db( $u );
}
*LJ::User::trust_list = \&trust_list;


# returns hashref;
#
#   { userid =>
#      { groupmask => NNN, fgcolor => '#xxx', bgcolor => '#xxx', showbydefault => NNN }
#   }
#
# one entry in the hashref for everything the given user has in a particular trust
# group.  you can specify the group by id or name.
#
# arguments is a hash of options
#    id => 1,                if set, get members of trust group id 1
#    name => "Foo Group",    if set, get members of trust group "Foo Group"
#    memcache_only => 1,     if set, never hit database
#    force_database => 1,    if set, ALWAYS hit database (DANGER)
#
sub trust_group_list {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    my $memc_only = delete $args{memcache_only} || 0;
    my $db_only = delete $args{force_database} || 0;
    my $name = delete $args{name};
    my $id = delete $args{id};
    confess 'extra/invalid arguments' if %args;
    confess 'need one of: id, name' unless $id || $name;
    confess 'do not need both: id, name' if $id && $name;

    # special case, we can disable loading friends for a user if there is a site
    # problem or some other issue with this codebranch
    return undef if $LJ::FORCE_EMPTY_FRIENDS{ $u->id };

    # load the user's groups
    my $grp = $u->trust_groups( id => $id, name => $name );
    return {} unless $grp;

    # calculate mask to use later
    my $mask = 1 << $grp->{groupnum};

    # attempt memcache if allowed
    unless ( $db_only ) {
        my $memc = DW::User::Edges::WatchTrust::Loader::_trust_group_list_memc( $mask, $u );
        return $memc if $memc;
    }

    # bail early if we are supposed to only hit memcache, this saves us from a
    # potentially expensive database call in codepaths that are best-effort
    return {} if $memc_only;

    # damn you memcache for not having our data
    return DW::User::Edges::WatchTrust::Loader::_trust_group_list_db( $mask, $u );
}
*LJ::User::trust_group_list = \&trust_group_list;


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
#   id => NNN,      id of group to get
#   name => "ZZZ",  name of group to get
#
# returns undef if group not found
#
sub trust_groups {
    my ( $u, %opts ) = @_;
    my $u = LJ::want_user( $u )
        or confess 'invalid user object';
    my $bit = delete( $opts{id} )+0;
    confess 'invalid bit number' if $bit < 0 || $bit > 60;
    my $name = lc delete( $opts{name} );
    confess 'invalid arguments' if %opts;

    return DW::User::Edges::WatchTrust::Loader::_trust_groups( $u, $bit, $name );
}
*LJ::User::trust_groups = \&trust_groups;


# edits a new trust_group, arguments is a hash of options
#   id => NNN,           (optional) bit/ID of the group to edit (1..60)
#   groupname => "ZZZ",  name of this group
#   sortorder => NNN,    (optional) sort order (0..255)
#   is_public => 1/0,    (optional) defaults to 0
#
# arguments are used to create the group.  if you don't specify an id then one
# will be automatically created for you.
#
# returns id of new group.
#
sub create_trust_group {
    my ( $u, %opts ) = @_;
    my $u = LJ::want_user( $u )
        or confess 'invalid user object';
    my $grp = $u->trust_groups;

    # calculate an id to use
    my $id = delete( $opts{id} )+0;
    confess 'group with that id already exists'
        if $id > 0 && exists $grp->{$id};
    ($id) ||= (grep { ! exists $grp->{$_} } 1..60)[0];
    confess 'id invalid'
        if $id < 1 || $id > 60;

    # validate other parameters
    confess 'invalid sortorder (not in range 0..255)'
        if exists $opts{sortorder} && $opts{sortorder} !~ /^\d+$/;
    confess 'invalid is_public (not 1/0)'
        if exists $opts{is_public} && $opts{is_public} !~ /^(?:0|1)$/;

    # need a name
    $opts{groupname} = DW::User::Edges::WatchTrust::valid_group_name( $opts{groupname} );
    confess 'name not provided'
        unless $opts{groupname};

    # now perform an edit with our chosen id
    return $id
        if $u->edit_trust_group( id => $id, _force_create => 1, %opts );
    return 0;
}
*LJ::User::create_trust_group = \&create_trust_group;


# edits a new trust_group, arguments is a hash of options
#   id => NNN,           bit/ID of the group to edit (1..60)
#   groupname => "ZZZ",  (optional) name of this group
#   sortorder => NNN,    (optional) sort order (0..255)
#   is_public => 1/0,    (optional) defaults to 0
#
# arguments are used to update the group, if you don't specify a particular
# parameter then we won't update that column.
#
# returns 1/0.
#
sub edit_trust_group {
    my ( $u, %opts ) = @_;
    my $u = LJ::want_user( $u )
        or confess 'invalid user object';
    my $id = delete( $opts{id} )+0;
    confess 'invalid id number' if $id < 0 || $id > 60;

    # and just in case they didn't tell us to change anything...
    return 1 unless %opts;

    # get current trust groups
    my $grps = $u->trust_groups;
    return 0 unless exists $grps->{$id} || $opts{_force_create};

    # now calculate what to change
    my %change = (
            sortorder => $grps->{$id}->{sortorder},
            groupname => $grps->{$id}->{groupname},
            is_public => $grps->{$id}->{is_public},
        );
    $change{sortorder} = $opts{sortorder}
        if exists $opts{sortorder} && $opts{sortorder} =~ /^\d+$/;
    $change{groupname} = DW::User::Edges::WatchTrust::valid_group_name( $opts{groupname} )
        if exists $opts{groupname};
    $change{is_public} = $opts{is_public}
        if exists $opts{is_public} && $opts{is_public} =~ /^(?:0|1)$/;

    # update the database
    my $dbcm = LJ::get_cluster_master( $u )
        or confess 'unable to connect to user cluster master';
    $dbcm->do( 'REPLACE INTO trust_groups (userid, groupnum, groupname, sortorder, is_public) VALUES (?, ?, ?, ?, ?)',
               undef, $u->id, $id, $change{groupname}, $change{sortorder} || 50, $change{is_public} || 0 );
    confess $dbcm->errstr if $dbcm->err;

    # kill memcache and return
    LJ::memcache_kill( $u, 'trust_group' );
    return 1;
}
*LJ::User::edit_trust_group = \&edit_trust_group;


# alters a trustmask to munge someone's group membership
#
#   $u->edit_trustmask( $otheru, ARGUMENTS )
#
# where ARGUMENTS can be one or more of:
#
#   set => [ 1, 3 ]        put $otheru in groups 1 and 3 only, remove from others
#   add => [ 1, 3 ]        add $otheru to groups 1 and 3
#   remove => [ 1, 3 ]     remove $otheru from groups 1 and 3
#
# if you are only adding/removing/setting a single group, you may pass the argument
# as a single number, not an arrayref.  e.g.,
#
#   $u->edit_trustmask( $otheru, add => 5 )
#
# adds $otheru to group 5.
#
# NOTE: passing the 'set' argument will override 'add' and 'remove' so they have no
# effect in the same call.  (so use either set or add/remove.  not both.)
#
# returns 1 on success, 0 on error.
#
sub edit_trustmask {
    my ( $u, $tu, %opts ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    $tu = LJ::want_user( $tu ) or confess 'invalid target user object';
    return 0 unless $u->trusts( $tu );

    # there's got to be a better way of doing this... but we want our arrays to only
    # contain valid group ids
    my @add = grep { $_ >= 1 && $_ <= 60 } map { $_ + 0 } @{ ref $opts{add} ? $opts{add} : [$opts{add}] };
    my @del = grep { $_ >= 1 && $_ <= 60 } map { $_ + 0 } @{ ref $opts{remove} ? $opts{remove} : [$opts{remove}] };
    my @set = grep { $_ >= 1 && $_ <= 60 } map { $_ + 0 } @{ ref $opts{set} ? $opts{set} : [$opts{set}] };
    my $do_clear = ( ref $opts{set} eq 'ARRAY' && scalar( @set ) == 0 ) ? 1 : 0;
    return 1 unless @add || @del || @set || $do_clear;

    # this is a special case, they said "set => []" with an empty arrayref,
    # so we remove this person's membership from all groups
    if ( $do_clear ) {
        $u->trustmask( $tu, 0 );
        return 1;
    }

    # if we're only doing a set, we can do that easily too
    if ( @set ) {
        my $mask = 0;
        $mask += ( 1 << $_ ) foreach @set;
        $u->trustmask( $tu, $mask );
        return 1;
    }

    # hard path, we need to break down a user's mask and then update it
    # and send out a new one
    my $mask = $u->trustmask( $tu );
    my %groups = map { $_ => 1 } grep { $mask & ( 1 << $_ ) } 1..60;

    # now process adds/deletes
    $groups{$_} = 1 foreach @add;
    delete $groups{$_} foreach @del;

    # now set it back and we're done
    my $mask = 0;
    $mask += ( 1 << $_ ) foreach keys %groups;
    $u->trustmask( $tu, $mask );
    return 1;
}
*LJ::User::edit_trustmask = \&edit_trustmask;


# give a user and a group, returns if they are in that group
sub trust_group_contains {
    my ( $u, $tu, $gid ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    $tu = LJ::want_user( $tu ) or confess 'invalid target user object';
    $gid = $gid + 0;

    return 0 unless $gid >= 1 && $gid <= 60;
    return 1 if $u->trustmask( $tu ) & ( 1 << $gid );
    return 0;
}
*LJ::User::trust_group_contains = \&trust_group_contains;


# returns 1/0 depending on if the source is allowed to add a trust edge
# to the target.  note: if you don't pass a target user, then we return
# a generic 1/0 meaning "this account is allowed to have a trust edge".
sub can_trust {
    my ( $u, $tu ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    $tu = LJ::want_user( $tu );

    # only individuals are allowed to trust eachother
    return 0 if ! $u->is_individual || ( $tu && ! $tu->is_individual );

    # both must be visible
    return 0 if ! $u->is_visible || ( $tu && ! $tu->is_visible );

    # that was simple...
    return 1;
}
*LJ::User::can_trust = \&can_trust;


# returns 1/0 depending on if the source is allowed to add a watch edge
# to the target.  note: if you don't pass a target user, then we return
# a generic 1/0 meaning "this account is allowed to have a watch edge".
sub can_watch {
    my ( $u, $tu ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    $tu = LJ::want_user( $tu );

    # only individuals are allowed to watch
    return 0 unless $u->is_individual;

    # both must be visible
    return 0 if ! $u->is_visible || ( $tu && ! $tu->is_visible );

    # and you're not allowed to watch identity accounts (they can't post)
    return 0 if $tu && $tu->is_identity;

    # that was kinda simple...
    return 1;
}
*LJ::User::can_watch = \&can_watch;







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
