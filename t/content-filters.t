#!/usr/bin/perl

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Test qw (temp_user);

plan tests => 12;

my $u1 = temp_user();
my $u2 = temp_user();

my ( $filter, $fid, $data, @f );

# reset, delete, etc
sub rst {
    foreach my $u ( $u1, $u2 ) {
        foreach my $tbl ( qw/ content_filters content_filter_data / ) {
            $u->do( "DELETE FROM $tbl WHERE userid = ?", undef, $u->id );
        }

        foreach my $mc ( qw/ content_filters / ) {
            LJ::memcache_kill( $u, $mc );
        }
    }
}

################################################################################
rst();
@f = $u1->content_filters;
ok( $#f == -1, 'no filters' );  # empty list

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
ok( ! defined $filter, 'get bogus filter' );

@f = $u1->content_filters;
ok( $#f == 1, 'get both filters' );

################################################################################
$filter = $u1->content_filters( name => 'foob' );
$data = $filter->data;
ok( defined $data && ref $data eq 'HASH' && scalar keys %$data == 0,
    'get data, is empty' );

################################################################################
$filter = $u1->content_filters( name => 'foob' );
ok( $filter->add_row( userid => $u2->id ) == 1, 'add a row' );

$filter = $u1->content_filters( name => 'foob' );
$data = $filter->data;
ok( $data && exists $data->{$u2->id}, 'get data, has u2' );

################################################################################
$fid = $u1->delete_content_filter( name => 'foob' );
ok( $fid > 0, 'delete filter' );

################################################################################
