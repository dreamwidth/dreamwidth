# t/wtf.t
#
# Test TODO WTF system - what aspects?
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 67;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Community;
use LJ::Test qw (temp_user temp_comm);

my $u1 = temp_user();
my $u2 = temp_user();
my $uc = temp_comm();
ok( $uc->is_community, 'uc is community' );

my ( $row, $hr, @ids );
my $dbh = LJ::get_db_writer();

# reset, delete, etc
sub rst {

    # global tables
    $dbh->do( 'DELETE FROM wt_edges WHERE from_userid = ? OR to_userid = ?', undef, $_, $_ )
        foreach ( $u1->id, $u2->id, $uc->id );
    $dbh->do( 'DELETE FROM reluser WHERE userid = ? OR targetid = ?', undef, $_, $_ )
        foreach ( $u1->id, $u2->id, $uc->id );

    # clustered tables
    $_->writer->do( 'DELETE FROM trust_groups WHERE userid = ?', undef, $_->id )
        foreach ( $u1, $u2, $uc );

    foreach my $u ( $u1, $u2, $uc ) {
        foreach my $mc (qw/ trust_group wt_list /) {
            LJ::memcache_kill( $u, $mc );
        }
    }
}

# print error and exit if database fails
sub dberr {
    if ( $dbh->err ) {
        diag( $dbh->errstr );
        exit 1;
    }
}

################################################################################
rst();
$u1->add_edge( $u2, watch => { fgcolor => 123, bgcolor => 321, nonotify => 1 } );
$row = $dbh->selectrow_array(
'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ? AND fgcolor = ? AND bgcolor = ? AND groupmask = ?',
    undef, $u1->id, $u2->id, 123, 321, 1 << 61
);
dberr();
ok( $row > 0, 'add to watch list' );

################################################################################
rst();
$u1->add_edge( $u2, trust => { mask => 30004, nonotify => 1 } );
$row = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ? AND groupmask = ?',
    undef, $u1->id, $u2->id, 30004 | 1 );
dberr();
ok( $row > 0, 'add to trust list' );

################################################################################
@ids = $u1->watched_userids;
ok( scalar(@ids) == 0, 'watched_userids empty' );

@ids = $u1->trusted_userids;
ok( scalar(@ids) == 1, 'trusted_userids one member' );

$hr = $u1->trust_list;
ok( scalar( keys %$hr ) == 1, 'trust_list one member' );

@ids = $u1->mutually_trusted_userids;
ok( scalar(@ids) == 0, 'mutually_trusted_userids empty' );

################################################################################
$u2->add_edge( $u1, trust => { mask => 30008, nonotify => 1 } );
$row = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ? AND groupmask = ?',
    undef, $u2->id, $u1->id, 30008 | 1 );
dberr();
ok( $row > 0, 'add to trust list reverse' );

@ids = $u1->mutually_trusted_userids;
ok( scalar(@ids) == 1, 'u1 mutually_trusted_userids one member' );

@ids = $u2->mutually_trusted_userids;
ok( scalar(@ids) == 1, 'u2 mutually_trusted_userids one member' );

################################################################################
$u1->remove_edge( $u2, trust => { nonotify => 1 } );
$row = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ? AND groupmask = ?',
    undef, $u1->id, $u2->id, 30004 | 1 );
dberr();
ok( $row == 0, 'remove from trust list' );

@ids = $u1->trusted_userids;
ok( scalar(@ids) == 0, 'trusted_userids empty' );

$hr = $u1->trust_list;
ok( scalar( keys %$hr ) == 0, 'trust_list empty' );

################################################################################
$u1->add_edge( $u2, watch => { nonotify => 1 }, trust => { nonotify => 1 } );
$row = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ? AND groupmask = ?',
    undef, $u1->id, $u2->id, ( 1 << 61 ) | 1 );
dberr();
ok( $row > 0, 'add to both lists (simultaneous)' );

################################################################################
@ids = $u1->watched_userids;
ok( scalar(@ids) == 1, 'u1 watched_userids one member' );

@ids = $u1->trusted_userids;
ok( scalar(@ids) == 1, 'u1 trusted_userids one member' );

@ids = $u2->watched_by_userids;
ok( scalar(@ids) == 1, 'u2 watched_by_userids one member' );

@ids = $u2->trusted_by_userids;
ok( scalar(@ids) == 1, 'u2 trusted_by_userids one member' );

################################################################################
$u1->add_edge( $u1, trust => { nonotify => 1 } );

$hr = $u1->watch_list;
ok( scalar( keys %$hr ) == 1, 'watch_list one member' );

################################################################################
rst();
$u1->add_edge( $u2, watch => { nonotify => 1 } );
$u1->add_edge( $u2, trust => { nonotify => 1 } );
$row = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ? AND groupmask = ?',
    undef, $u1->id, $u2->id, ( 1 << 61 ) | 1 );
dberr();
ok( $row > 0, 'add to both lists (one by one)' );

################################################################################
@ids = $u1->watched_userids;
ok( scalar(@ids) == 1, 'u1 watched_userids one member' );

@ids = $u1->trusted_userids;
ok( scalar(@ids) == 1, 'u1 trusted_userids one member' );

@ids = $u2->watched_by_userids;
ok( scalar(@ids) == 1, 'u2 watched_by_userids one member' );

@ids = $u2->trusted_by_userids;
ok( scalar(@ids) == 1, 'u2 trusted_by_userids one member' );

$hr = $u1->watch_list;
ok( scalar( keys %$hr ) == 1, 'watch_list one member' );

################################################################################
rst();
$u1->add_edge( $u2, trust => { mask => 30004, nonotify => 1 }, watch => { nonotify => 1 } );
$row =
    $dbh->selectrow_array( 'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
    undef, $u1->id, $u2->id );
dberr();
ok( $row > 0, 'add to both lists with trustmask' );

################################################################################
$u1->remove_edge( $u2, watch => { nonotify => 1 } );
$row =
    $dbh->selectrow_array( 'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
    undef, $u1->id, $u2->id );
dberr();
ok( $row > 0, 'remove from watch list; still on trust list' );

################################################################################
@ids = $u1->watched_userids;
ok( scalar(@ids) == 0, 'watched_userids empty' );

@ids = $u1->trusted_userids;
ok( scalar(@ids) == 1, 'trusted_userids one member' );

################################################################################
rst();
$u1->add_edge( $u2, watch => { fgcolor => 255, bgcolor => 255, nonotify => 1 } );
$row =
    $dbh->selectrow_array( 'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
    undef, $u1->id, $u2->id );
dberr();
ok( $row > 0, 'add to watch list with colors' );

$hr = $u1->watch_list;
ok( scalar( keys %$hr ) == 1, 'watch_list one member' );
is( $hr->{ $u2->id }->{fgcolor}, '#0000ff', 'fgcolor ok' );
is( $hr->{ $u2->id }->{bgcolor}, '#0000ff', 'bgcolor ok' );

################################################################################
$u1->add_edge( $u2, watch => { nonotify => 1 } );
$row =
    $dbh->selectrow_array( 'SELECT COUNT(*) FROM wt_edges WHERE from_userid = ? AND to_userid = ?',
    undef, $u1->id, $u2->id );
dberr();
ok( $row > 0, 'readd to watch list' );

$hr = $u1->watch_list;
ok( scalar( keys %$hr ) == 1, 'watch_list one member' );
is( $hr->{ $u2->id }->{fgcolor}, '#0000ff', 'fgcolor still ok' );
is( $hr->{ $u2->id }->{bgcolor}, '#0000ff', 'bgcolor still ok' );

################################################################################
rst();
$u1->create_trust_group( groupname => 'foo group', sortorder => 10, is_public => 1 );
$row = $u1->writer->selectrow_array(
'SELECT COUNT(*) FROM trust_groups WHERE userid = ? AND groupname = ? AND sortorder = ? AND is_public = ?',
    undef, $u1->id, 'foo group', 10, 1
);
dberr();
ok( $row > 0, 'create trust group' );

$hr = $u1->trust_groups;
ok( scalar( keys %$hr ) > 0, 'get trust group' );

################################################################################
$u1->edit_trust_group( id => 1, groupname => 'bar group' );
$row = $u1->writer->selectrow_array(
'SELECT COUNT(*) FROM trust_groups WHERE userid = ? AND groupname = ? AND sortorder = ? AND is_public = ?',
    undef, $u1->id, 'bar group', 10, 1
);
dberr();
ok( $row > 0, 'edit trust group' );

$hr = $u1->trust_groups;
is( $hr->{1}->{groupname}, 'bar group', 'check new group name' );

################################################################################
rst();

# have to create a group with a known id for these tests
$u1->edit_trust_group( id => 1, groupname => 'bar group', _force_create => 1 );

$u1->add_edge( $u2, trust => { nonotify => 1 } );
ok( $u1->trustmask($u2) == 1, 'validate trustmask == 1' );

$hr = $u1->trust_group_members( id => 1 );
ok( scalar( keys %$hr ) == 0, 'validate nobody in group 1' );

################################################################################
$u1->edit_trustmask( $u2, add => 1 );
ok( $u1->trustmask($u2) == 3, 'add to group, validate trustmask == 3' );

$hr = $u1->trust_group_members( id => 1 );
ok( scalar( keys %$hr ) == 1, 'validate one member in group 1' );

################################################################################
$u1->edit_trustmask( $u2, add => [ 1, 3 ] );
ok( $u1->trustmask($u2) == 11, 'add more groups' );

$u1->edit_trustmask( $u2, remove => [1] );
ok( $u1->trustmask($u2) == 9, 'remove one group' );

$u1->edit_trustmask( $u2, set => [ 4, 3 ] );
ok( $u1->trustmask($u2) == 25, 'set groups' );

ok( $u1->trust_group_contains( $u2, 3 ) == 1, 'group 3 contains u2' );
ok( $u1->trust_group_contains( $u2, 4 ) == 1, 'group 4 contains u2' );
ok( $u1->trust_group_contains( $u2, 5 ) == 0, 'group 5 does not contain u2' );

################################################################################

# have to create a group with a known id for these tests
$u1->edit_trust_group( id => 3, groupname => 'bar group 3', _force_create => 1 );

ok( $u1->trust_group_contains( $u2, 3 ) == 1, 'group 3 contains u2' );
ok( $u1->trust_group_contains( $u2, 4 ) == 1, 'group 4 contains u2' );
ok( $u1->trust_group_contains( $u2, 5 ) == 0, 'group 5 does not contain u2' );

# now delete the group
ok( $u1->delete_trust_group( name => 'bar group 3' ), 'delete trust group 3' );

ok( $u1->trust_group_contains( $u2, 3 ) == 0, 'group 3 does not contain u2' );
ok( $u1->trust_group_contains( $u2, 4 ) == 1, 'group 4 contains u2' );
ok( $u1->trust_group_contains( $u2, 5 ) == 0, 'group 5 does not contain u2' );

ok( !$u1->trust_groups( name => 'bar group 3' ), 'validate group is gone' );

$u1->edit_trustmask( $u2, set => [] );
ok( $u1->trustmask($u2) == 1, 'clear groups' );

################################################################################
rst();
$u1->add_edge( $u2, trust => { mask => 12, nonotify => 1 } );
ok( $u1->trustmask($u2) == 13, 'add with trust mask' );

$u1->add_edge( $u2, trust => { nonotify => 1 } );
ok( $u1->trustmask($u2) == 13, 'add edge again, test mask' );

################################################################################
ok( $u1->can_watch      && $u2->can_trust,      'allowed to watch and trust' );
ok( $u1->can_watch($u2) && $u2->can_trust($u1), 'allowed to watch and trust the other' );

################################################################################
rst();
$u1->add_edge( $uc, member => {} );
ok( scalar( $uc->member_userids ) == 1, 'join community' );

$hr = $uc->watch_list;
ok( scalar( keys %$hr ) == 0, 'community watch list has zero' );

$hr = $uc->watch_list( community_okay => 1 );
ok( scalar( keys %$hr ) == 1, 'community watch list has one' );

################################################################################
