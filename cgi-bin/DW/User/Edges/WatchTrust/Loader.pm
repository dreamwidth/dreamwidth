#!/usr/bin/perl
#
# DW::User::Edges::WatchTrust::Loader
#
# Helper functions for loading data from memcache and the database for watch and
# trust edge data.  These functions are not directly callable by users, only
# the WatchTrust edge system should call these.
#
# DO NOT CALL THESE FUNCTIONS FROM OUTSIDE THE WT SYSTEM.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::User::Edges::WatchTrust::Loader;
use strict;

use Carp qw/ confess /;

# returns trustmask between two users
sub _trustmask {
    my ( $from_userid, $to_userid ) = @_;

    my $memkey = [ $from_userid, "trustmask:$from_userid:$to_userid" ];
    my $mask   = LJ::MemCache::get($memkey);
    unless ( defined $mask ) {
        my $dbr = LJ::get_db_reader();
        die "No database reader available" unless $dbr;

        $mask = $dbr->selectrow_array(
            'SELECT groupmask FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
            undef, $from_userid, $to_userid );
        return 0 if $dbr->err;
        $mask = $mask ? $mask + 0 : 0;    # force numeric

        LJ::MemCache::set( $memkey, $mask, 3600 );
    }

    return $mask;
}

# actually get friend/friendof uids, should not be called directly
# FYI: in original LJ this function had a Gearman ability that was dropped when we
# migrated to DW.  that functionality might be necessary for load reasons for large
# communities in the future and may need to be readded.
sub _wt_userids {
    my ( $u, %args ) = @_;

    my $limit   = int( delete $args{limit} ) || 50000;
    my $mode    = delete $args{mode};
    my $reverse = delete $args{reverse} || 0;
    confess 'unknown option' if %args;

    my $sql;
    my $memkey;

    if ( $mode eq 'watch' ) {
        if ($reverse) {
            $sql =
"SELECT from_userid FROM wt_edges WHERE to_userid=? AND groupmask & 1<<61 LIMIT $limit";
            $memkey = [ $u->id, "watched_by:" . $u->id ];
        }
        else {
            $sql =
"SELECT to_userid FROM wt_edges WHERE from_userid=? AND groupmask & 1<<61 LIMIT $limit";
            $memkey = [ $u->id, "watched:" . $u->id ];
        }

    }
    elsif ( $mode eq 'trust' ) {
        if ($reverse) {
            $sql =
                "SELECT from_userid FROM wt_edges WHERE to_userid=? AND groupmask & 1 LIMIT $limit";
            $memkey = [ $u->id, "trusted_by:" . $u->id ];
        }
        else {
            $sql =
                "SELECT to_userid FROM wt_edges WHERE from_userid=? AND groupmask & 1 LIMIT $limit";
            $memkey = [ $u->id, "trusted:" . $u->id ];
        }

    }
    else {
        confess "mode must either be 'watch' or 'trust'";
    }

    if ( my $pack = LJ::MemCache::get($memkey) ) {
        my ( $slimit, @uids ) = unpack( "N*", $pack );

        # value in memcache is good if stored limit (from last time)
        # is >= the limit currently being requested.  we just may
        # have to truncate it to match the requested limit
        if ( $slimit >= $limit ) {
            @uids = @uids[ 0 .. $limit - 1 ] if @uids > $limit;
            return @uids;
        }

        # value in memcache is also good if number of items is less
        # than the stored limit... because then we know it's the full
        # set that got stored, not a truncated version.
        return @uids if @uids < $slimit;
    }

    my $dbr  = LJ::get_db_reader();
    my $uids = $dbr->selectcol_arrayref( $sql, undef, $u->id );

    # if the list of uids is greater than 950k
    # -- slow but this definitely works
    my $pack = pack( "N*", $limit );
    foreach (@$uids) {
        last if length $pack > 1024 * 950;
        $pack .= pack( "N*", $_ );
    }

    LJ::MemCache::add( $memkey, $pack, 3600 ) if $uids;

    return @$uids;
}

# helper to filter the _wt_list by a groupmask AND
sub _filter_wt_list {
    my ( $mask, $raw ) = @_;
    return {}    unless $mask;                                # undef/0 = no matches!
    return undef unless defined $raw && ref $raw eq 'HASH';
    return $raw  unless keys %$raw;

    return {
        map      { $_ => $raw->{$_} }
            grep { $raw->{$_}->{groupmask} & $mask }
            keys %$raw
    };
}

# helper, simply passes down to _wt_list_memc and filters
sub _watch_list_memc          { return _filter_wt_list( 1 << 61, _wt_list_memc(@_) ); }
sub _watch_list_db            { return _filter_wt_list( 1 << 61, _wt_list_db(@_) ); }
sub _trust_list_memc          { return _filter_wt_list( 1,       _wt_list_memc(@_) ); }
sub _trust_list_db            { return _filter_wt_list( 1,       _wt_list_db(@_) ); }
sub _trust_group_members_memc { return _filter_wt_list( shift(), _wt_list_memc(@_) ); }
sub _trust_group_members_db   { return _filter_wt_list( shift(), _wt_list_db(@_) ); }

# attempt to load a user's watch list from memcache
sub _wt_list_memc {
    my ( $u, %args ) = @_;

    # variable setup
    my %rows;    # rows to be returned
    my $userid  = $u->id;       # helper to use it a lot
    my $ver     = 2;            # memcache data version
    my $packfmt = "NH6H6QC";    # pack format
    my $packlen = 19;           # length of $packfmt in bytes
    my @cols = qw/ to_userid fgcolor bgcolor groupmask showbydefault /;

    # first, check memcache
    my $key     = ( $args{community_okay} && $u->is_community ) ? 'c_wt_list' : 'wt_list';
    my $memkey  = [ $userid, "$key:$userid" ];
    my $memdata = LJ::MemCache::get($memkey);
    return undef unless $memdata;

    # first byte of object is data version
    # only version 1 is meaningful right now
    my $memver = substr( $memdata, 0, 1, '' );
    return undef unless $memver == $ver;

    # get each $packlen-byte row
    while ( length($memdata) >= $packlen ) {
        my @row = unpack( $packfmt, substr( $memdata, 0, $packlen, '' ) );

        # add "#" to beginning of colors
        $row[$_] = "\#$row[$_]" foreach 1 .. 2;

        # turn unpacked row into hashref
        my $to_userid = $row[0];
        my $idx       = 1;
        foreach my $col ( @cols[ 1 .. $#cols ] ) {
            $rows{$to_userid}->{$col} = $row[ $idx++ ];
        }
    }

    # got from memcache, return
    return \%rows;
}

# attempt to load a user's watch list from the database
sub _wt_list_db {
    my ( $u, %args ) = @_;

    my $userid = $u->id;
    my $dbh    = LJ::get_db_writer();

    my $lockname     = "get_wt_list:$userid";
    my $release_lock = sub {
        LJ::DB::release_lock( $dbh, "global", $lockname );
        return $_[0];
    };

    # get a lock
    my $lock = LJ::DB::get_lock( $dbh, "global", $lockname );
    return {} unless $lock;

    # in lock, try memcache first (unless told not to)
    my $memc =
        $args{force_database}
        ? undef
        : _wt_list_memc( $u, community_okay => $args{community_okay} );
    return $release_lock->($memc) if $memc;

    # we are now inside the lock, but memcache was empty, so we must query
    # the database to get the data

    # memcache data info
    my $ver = 2;    # memcache data version
    my $key    = ( $args{community_okay} && $u->is_community ) ? 'c_wt_list' : 'wt_list';
    my $memkey = [ $userid, "$key:$userid" ];
    my $packfmt = "NH6H6QC";    # pack format
    my $packlen = 19;           # length of $packfmt

    # columns we're selecting
    my $mempack = $ver;         # full packed string to insert into memcache, byte 1 is dversion
    my %rows;                   # rows object to be returned, all groupmasks match

    # at this point we branch.  if we're trying to get the list of things the community
    # watches - for usage in the friends page only - then we change paths.
    if ( $u->is_community && $args{community_okay} ) {

        # simply get userids from elsewhen to build %rows
        foreach my $uid ( $u->member_userids ) {

            # pack data into list, but only store up to 950k of data before
            # bailing.  (practical limit of 64k watch list entries.)
            #
            # also note that we fake a lot of this, since communities don't actually
            # have a watch list.
            my $newpack = pack( $packfmt, ( $uid, '000000', 'ffffff', 1 << 61, '1' ) );
            last if length($mempack) + length($newpack) > 950 * 1024;

            $mempack .= $newpack;

            # more faking it for fun and profit
            $rows{$uid} = {
                to_userid     => $uid,
                fgcolor       => '#000000',
                bgcolor       => '#ffffff',
                groupmask     => 1 << 61,
                showbydefault => '1',
            };
        }

        # now stuff in memcache and bail
        LJ::MemCache::set( $memkey, $mempack );
        return $release_lock->( \%rows );
    }

    # at this point, if they're not an individual, then throw an empty set of data in memcache
    # and bail out.  only individuals have watch lists.
    unless ( $u->is_individual ) {
        LJ::MemCache::set( $memkey, $mempack );
        return $release_lock->( \%rows );
    }

    # actual watching path
    my @cols = qw/ to_userid fgcolor bgcolor groupmask showbydefault /;

    # try the SQL on the master database
    my $sth = $dbh->prepare( 'SELECT to_userid, fgcolor, bgcolor, groupmask, showbydefault '
            . 'FROM wt_edges WHERE from_userid = ?' );
    $sth->execute($userid);
    confess $dbh->errstr if $dbh->err;

    # iterate over each row and prepare result
    while ( my @row = $sth->fetchrow_array ) {

        # convert color columns to hex
        $row[$_] = sprintf( "%06x", $row[$_] ) foreach 1 .. 2;

        # pack data into list, but only store up to 950k of data before
        # bailing.  (practical limit of 64k watch list entries.)
        my $newpack = pack( $packfmt, @row );
        last if length($mempack) + length($newpack) > 950 * 1024;

        $mempack .= $newpack;

        # add "#" to beginning of colors
        $row[$_] = "\#$row[$_]" foreach 1 .. 2;

        my $to_userid = $row[0];
        my $idx       = 1;
        foreach my $col ( @cols[ 1 .. $#cols ] ) {
            $rows{$to_userid}->{$col} = $row[ $idx++ ];
        }
    }

    # now stuff in memcache
    LJ::MemCache::set( $memkey, $mempack );

    # finished with lock, release it
    return $release_lock->( \%rows );
}

# returns a hashref for a trust group
sub _trust_groups {
    my ( $u, $bit, $name ) = @_;

    # memcache data version number
    my $ver = 2;

    # helper function for iterating through groups
    my $fg;
    my $find_grp = sub {

        # $fg format:
        # [ version, [userid, bitnum, name, sortorder, public], [...], ... ]

        my $memver = shift @$fg;
        return undef unless $memver == $ver;

        # bit number was specified
        if ($bit) {
            foreach (@$fg) {
                return LJ::MemCache::array_to_hash( 'trust_group', [ $memver, @$_ ] )
                    if $_->[1] == $bit;
            }
            return undef;
        }

        # group name was specified
        if ($name) {
            foreach (@$fg) {
                return LJ::MemCache::array_to_hash( 'trust_group', [ $memver, @$_ ] )
                    if lc( $_->[2] ) eq $name;
            }
            return undef;
        }

        # no arg, return entire object
        if (wantarray) {    # group list sorted by sortorder || name order
            return map { LJ::MemCache::array_to_hash( 'trust_group', [ $memver, @$_ ] ) }
                sort { $a->[3] <=> $b->[3] || $a->[2] cmp $b->[2] } @$fg;
        }
        else {              # ref to hash keyed by bitnum
            return {
                map { $_->[1] => LJ::MemCache::array_to_hash( 'trust_group', [ $memver, @$_ ] ) }
                    @$fg
            };
        }
    };

    # check memcache
    my $userid = $u->id;
    my $memkey = [ $userid, "trust_group:$userid" ];
    $fg = LJ::MemCache::get($memkey);
    return $find_grp->() if $fg;

    # check database
    $fg = [$ver];
    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $sth = $db->prepare( 'SELECT userid, groupnum, groupname, sortorder, is_public '
            . 'FROM trust_groups WHERE userid = ?' );
    $sth->execute($userid);
    return LJ::error($db) if $db->err;

    my @row;
    push @$fg, [@row] while @row = $sth->fetchrow_array;

    # set in memcache
    LJ::MemCache::set( $memkey, $fg );

    return $find_grp->();
}

1;
