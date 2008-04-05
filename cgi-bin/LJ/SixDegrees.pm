#!/usr/bin/perl
#

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

package LJ::SixDegrees;

sub find_path
{
    my ($fu, $tu, $timeout) = @_;
    return () unless $fu && $tu;
    return () unless $fu->{journaltype} eq "P" && $tu->{journaltype} eq "P";

    $LJ::SixDegrees::MEMC_EXPIRE ||= 86400;

    my $cache = {};  # keys for links in/out -> listrefs, userids -> $u's, "notes" -> why pass/fail
    $cache->{$fu->{userid}} = $fu;
    $cache->{$tu->{userid}} = $tu;

    my $memkey = [ $fu->{'userid'}, "6dpath:$fu->{userid}:$tu->{userid}" ];
    my $exp = 3600;
    my $path = LJ::MemCache::get($memkey);
    unless ($path) {
	$path = _find_path_helper($fu, $tu, $timeout, $cache);
	LJ::MemCache::set($memkey, $path, $exp) if $path;
    }

    return () unless $path;
    return map { $cache->{$_} || LJ::load_userid($_) } @$path;
}

# returns arrayref of userids in path on success (even if empty), or undef on timeout
sub _find_path_helper
{
    my ($fu, $tu, $timeout, $cache) = @_;

    my $time_start = time();

    # user is themselves (one element in path)
    return [$fu->{userid}] if $fu->{'userid'} == $tu->{'userid'};

    # from user befriends to user (two elements in path
    my $fu_friends = links_out($fu, $cache);
    if (intersect($fu_friends, [ $tu->{'userid'} ])) {
	$cache->{'note'} = "2 way path";
	return [$fu->{userid}, $tu->{userid}];
    }

    # try to find a three-way path (fu has a friend who lists tu as a friend)
    my $tu_friendofs = links_in($tu, $cache);
    if (my $via = intersect($fu_friends, $tu_friendofs)) {
	$cache->{'note'} = "3 way path";
	return [$fu->{userid}, $via, $tu->{userid}];
    }

    # try to find four-way path by expanding fu's friends' friends,
    # one at a time, looking for intersections.  along the way,
    # keep track of all friendsfriends, then we can walk along
    # tu's friendofs-friendofs looking for intersections there later
    # if necessary.
    my %friendsfriends = ();  # uid -> 1
    my %friends = ();         # uid -> 1
    my $tried = 0;
    foreach my $fid (@$fu_friends) {
	$friends{$fid} = 1;
	next if ++$tried > 100;
	if (time() > $time_start + $timeout) {
	    $cache->{'note'} = "timeout";
	    return undef;
	}

	# a group of one friend's ($fid's) friends
	my $ffset = links_out($fid, $cache);

	# see if $fid's friends intersect $tu's friendofs
	if (intersect($ffset, [ $tu->{userid} ])) {
	    $cache->{'note'} = "returning via fid's friends to tu";
	    return [$fu->{userid}, $fid, $tu->{userid}];
	}

	# see if $fid's friends intersect $tu's friendofs
	if (my $via = intersect($ffset, $tu_friendofs)) {
	    $cache->{'note'} = "returning via fid's friends to tu's friendofs";
	    return [$fu->{userid}, $fid, $via, $tu->{userid}];
	}
	
	# otherwise, track who's a friends-of-friend, and the friend we're on
	# so we don't try doing the same search later
	foreach (@$ffset) {
	    $friendsfriends{$_} ||= $fid;
	}
    }

    # try to find a path by looking at tu's friendof-friendofs
    $tried = 0;
    foreach my $foid (@$tu_friendofs) {
	last if ++$tried > 100;
	if (time() > $time_start + $timeout) {
	    $cache->{'note'} = "timeout";
	    return undef;
	}

	if (my $fid = $friendsfriends{$foid}) {
	    $cache->{'note'} = "returning via friend-of-friend is friend of target";
	    return [$fu->{userid}, $fid, $foid, $tu->{userid}];
	}

	my $foset = links_in($foid, $cache);
	
 	# see if we can go from $tu to $foid's friends.  (now, this shouldn't normally
	# happen, but we limit the links_in/out to 1000, so there's a possibility
	# we stopped during the friend-of-friend search above)
	if (intersect([ $fu->{userid} ], $foset)) {
	    $cache->{'note'} = "returning via friend-of-friend but discovered backwards";
	    return [$fu->{userid}, $foid, $tu->{userid}];
	}

	# otherwise, see if any of this group of friendof-friendofs are a friend-friend
	foreach my $uid (@$foset) {
	    if (my $fid = $friends{$uid}) {
		$cache->{'note'} = "returning via friend intersection with friendof-friendof";
		return [$fu->{userid}, $fid, $foid, $tu->{userid}];
	    }
	    if (my $fid = $friendsfriends{$uid}) {
		$cache->{'note'} = "returning via friend-of-friend intersection with friendof-friendof";
		return [$fu->{userid}, $fid, $uid, $foid, $tu->{userid}];
	    }
	}
    }

    return [];  # no path, but not a timeout (as opposed to undef above)
}

sub intersect
{
    my ($list_a, $list_b) = @_;
    return 0 unless ref $list_a && ref $list_b;
    my %temp;
    $temp{$_} = 1 foreach @$list_a;
    foreach (@$list_b) {
	return $_ if $temp{$_};
    }
    return 0;
}

sub link_fetch
{
    my ($uid, $key, $sql, $cache) = @_;

    # first try from the pre-load/already-done per-process cache
    return $cache->{$key} if defined $cache->{$key};
    
    # then try memcache
    my $memkey = [$uid, $key];
    my $listref = LJ::MemCache::get($memkey);
    if (ref $listref eq "ARRAY") {
	$cache->{$key} = $listref;
	return $listref;
    }

    # finally fall back to the database.
    my $dbr = LJ::get_db_reader();
    $listref = $dbr->selectcol_arrayref($sql, undef, $uid) || [];

    # get the $u's for everybody (bleh, since we need to know if they're a community
    # or not)
    my @need_load;   # userids necessary to load
    foreach my $uid (@$listref) {
	push @need_load, $uid unless $cache->{$uid};
    }
    if (@need_load) {
	LJ::load_userids_multiple([ map { $_, \$cache->{$_} } @need_load ]);
    }

    # filter out communities/deleted/suspended/etc
    my @clean_list;  # visible users, not communities
    foreach my $uid (@$listref) {
	my $u = $cache->{$uid};
	next unless $u && $u->{'statusvis'} eq "V" && $u->{'journaltype'} eq "P";
	push @clean_list, $uid;
    }

    $listref = \@clean_list;
    LJ::MemCache::set($memkey, $listref, $LJ::SixDegrees::MEMC_EXPIRE);
    $cache->{$key} = $listref;
    return $listref;
}

sub links_out
{
    my $uid = LJ::want_userid($_[0]);
    return link_fetch($uid, "6dlo:$uid",
		      "SELECT friendid FROM friends WHERE userid=? LIMIT 1000",
		      $_[1]);
}

sub links_in
{
    my $uid = LJ::want_userid($_[0]);
    return link_fetch($uid, "6dli:$uid",
		      "SELECT userid FROM friends WHERE friendid=? LIMIT 1000",
		      $_[1]);
}

1;
