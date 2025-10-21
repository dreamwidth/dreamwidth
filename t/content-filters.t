# t/content-filters.t
#
# Test user content filters.
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

use Test::More tests => 15;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw ( temp_user temp_comm );

use LJ::Community;

my $u1 = temp_user();
my $u2 = temp_user();

my ( $filter, $fid, $data, @f );

# reset, delete, etc
sub rst {
    foreach my $u ( $u1, $u2 ) {
        foreach my $tbl (qw/ content_filters content_filter_data /) {
            $u->do( "DELETE FROM $tbl WHERE userid = ?", undef, $u->id );
        }

        foreach my $mc (qw/ content_filters /) {
            LJ::memcache_kill( $u, $mc );
        }
    }
}

################################################################################
rst();
@f = $u1->content_filters;
ok( $#f == -1, 'no filters' );    # empty list

$fid = $u1->create_content_filter( name => 'foob', public => 1, sortorder => 13 );
ok( $fid > 0, 'make empty filter' );

$filter = $u1->content_filters( name => 'foob' );
is( $filter->name, 'foob', 'lookup filter 1 by name' );

################################################################################
$fid = $u1->create_content_filter( name => 'isfd', public => 0, sortorder => 31 );
ok( $fid > 0, 'make another filter' );

$filter = $u1->content_filters( id => $fid );
is( $filter->name, 'isfd', 'lookup filter 2 by id' );

$filter = $u1->content_filters( name => 'isfd' );
is( $filter->name, 'isfd', 'lookup filter 2 by name' );

################################################################################
$filter = $u1->content_filters( name => 'sodf' );
ok( !defined $filter, 'get bogus filter' );

@f = $u1->content_filters;
ok( $#f == 1, 'get both filters' );

################################################################################
$filter = $u1->content_filters( name => 'foob' );
$data   = $filter->data;
ok( defined $data && ref $data eq 'HASH' && scalar keys %$data == 0, 'get data, is empty' );

################################################################################
$filter = $u1->content_filters( name => 'foob' );
ok( $filter->add_row( userid => $u2->id ) == 1, 'add a row' );

$filter = $u1->content_filters( name => 'foob' );
$data   = $filter->data;
ok( $data && exists $data->{ $u2->id }, 'get data, has u2' );

################################################################################
$fid = $u1->delete_content_filter( name => 'foob' );
ok( $fid > 0, 'delete filter' );

################################################################################
note("in default filter after accepting a community invite");
{
    my $admin_u  = temp_user();
    my $comm_u   = temp_comm();
    my $invite_u = temp_user();

    LJ::set_rel( $comm_u, $admin_u, 'A' );
    LJ::start_request();

    $invite_u->create_content_filter( name => 'default' );

    my $filter;
    $filter = $invite_u->content_filters( name => 'default' );

    $invite_u->send_comm_invite( $comm_u, $admin_u, [qw ( member )] );
    ok(
        !$filter->contains_userid( $comm_u->userid ),
        "not in filter yet because invite hasen't been accepted"
    );

    $invite_u->accept_comm_invite($comm_u);
    ok( $filter->contains_userid( $comm_u->userid ), "accepted invite, now in filter" );
}

################################################################################
note("in default filter after creating a community");
{
    my $admin_u = temp_user();
    LJ::set_remote($admin_u);

    $admin_u->create_content_filter( name => 'default' );

    my $filter;
    $filter = $admin_u->content_filters( name => 'default' );

    my $comm_u = LJ::User->create_community(
        user       => "t_" . LJ::rand_chars( 15 - 2 ),
        membership => 'open',
        postlevel  => 'members',
    );
    ok( $filter->contains_userid( $comm_u->userid ),
        "newly created community should go into the admin's default filters" );
}

################################################################################
