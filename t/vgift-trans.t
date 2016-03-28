#!/usr/bin/perl
#
# t/vgift-trans.t
#
# Virtual gift transaction tests for shop backend.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2012-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw (temp_user);

use DW::VirtualGiftTransaction;

plan tests => 30;

my $u1 = temp_user();
my $u2 = temp_user();
my $ts = time();

# workaround: new_cart breaks if no uniq
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
local $LJ::MOGILEFS_CONFIG{hosts} = undef;  # not interested in testing images
local $LJ::T_SUPPRESS_EMAIL = 1;
local $LJ::SHOP{vgifts} = [];

my $error;

# make a vgift for testing - first with no name, then same name twice (7 tests)
my $vgift = DW::VirtualGift->create( error => \$error );
ok ( ! $vgift, 'vgift with no name not created' );
is ( $error, LJ::Lang::ml('vgift.error.create.noname'), 'expected error message' );

undef $error;

$vgift = DW::VirtualGift->create( name => "testing$ts", creatorid => $u1->id,
                                  custom => 'Y', error => \$error );
ok ( $vgift, 'vgift created' );
ok ( ! $error, 'no error message' );
ok ( $vgift->is_active, 'can only buy active gifts' );

my $dupe = DW::VirtualGift->create( name => "testing$ts", error => \$error );
ok ( ! $dupe, 'vgift with duplicate name not created' );
is ( $error, LJ::Lang::ml('vgift.error.create.samename'), 'expected error message' );

undef $error;

# attempt to fake a transaction (10 tests)
my $cart;
my %item_args = ( target_userid => $u1->id, from_userid => $u2->id, vgiftid => $vgift->id );
my $item = DW::Shop::Item::VirtualGift->new( %item_args );
ok ( $item, 'created shop item' );

if ( $item ) {
    $cart = DW::Shop::Cart->new_cart( $u2 );
    ok ( $cart, 'created new cart' );
}

if ( $item && $cart ) {
    $u1->ban_user_multi( $u2 );
    ok ( $u1->has_banned( $u2 ), 'banned' );
    my ( $ok, $rv ) = $cart->add_item( $item );
    ok ( ! $ok, "can't buy if banned user" );
    undef $cart if $ok;
    # make sure we unban, working around REQ_CACHE_REL persistence
    $u1->unban_user_multi( $u2 );
    delete $LJ::REQ_CACHE_REL{$u1->userid."-".$u2->userid."-B"};  # argh
    ok ( ! $u1->has_banned( $u2 ), 'unbanned' );
}

if ( $item && $cart ) {
    my ( $ok, $rv ) = $cart->add_item( $item );
    ok ( $ok, 'item added to cart' ) or diag( $rv );
    undef $cart unless $ok;
}

my ( $transid, $applied );

if ( $item && $cart ) {
    $cart->state( $DW::Shop::STATE_PAID );  # does transaction->save
    $transid = $item->vgift_transid;
    ok ( $transid, 'transaction OK' );
    cmp_ok ( $vgift->num_sold, '==', 1, "num_sold was incremented" );
}

if ( $transid ) {
    $applied = $item->apply;  # delivery process
    ok ( $applied, 'item applied' );
}

my $trans;

if ( $applied ) {
    $trans = DW::VirtualGiftTransaction->load( user => $u1, id => $transid );
    isa_ok ( $trans, 'DW::VirtualGiftTransaction' ) or undef $trans;
}

# check transaction values (7 tests)
if ( $trans && $trans->is_delivered ) {
    is ( $trans->{cartid}, $cart->id, 'cart ids match' );
    is ( $trans->from_text, $u2->display_name, 'text names match' );
    is ( $trans->from_html, $u2->ljuser_display, 'html names match' );

    my @list = DW::VirtualGiftTransaction->list( user => $u1 );
    cmp_ok ( scalar @list, '==', 1, "u1 has one gift" );
    is_deeply ( $trans, $list[0], 'transaction objects match' );

    @list = DW::VirtualGiftTransaction->list( user => $u1, profile => 1 );
    ok ( ! @list, "unaccepted gift not listed on profile" );
    $trans->accept;

    @list = DW::VirtualGiftTransaction->list( user => $u1, profile => 1 );
    cmp_ok ( scalar @list, '==', 1, "one gift on profile" );
}

# do clean up (2 tests) - can't delete cart, but do need to change state
$cart->state( $DW::Shop::STATE_PROCESSED ) if $cart;  # worker usually does this
my $removed = $trans ? $trans->remove : undef;  # deletes row from vgift_trans
ok ( $removed, 'deleted test transaction' );
ok ( ! DW::VirtualGiftTransaction->list( user => $u1 ), 'no gifts left' );

# now attempt to delete the vgift (4 tests)
BAIL_OUT('no vgift to delete') unless $vgift;
my $deleted = $vgift->delete;
ok ( ! $deleted, "can't delete active gift" );

$vgift->mark_inactive;
if ( $vgift->num_sold ) {
    $deleted = $vgift->delete;
    ok ( ! $deleted, "can't delete gift with num_sold" );
    # we don't have a mark_unsold, need to clear the rows manually
    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM vgift_counts WHERE vgiftid=?", undef, $vgift->id );
    die $dbh->errstr if $dbh->err;
    LJ::MemCache::delete( $vgift->num_sold_memkey );
}

$deleted = $vgift->delete( $u2 );
ok ( ! $deleted, "can't delete with non-permitted user" );

$deleted = $vgift->delete;  # defaults to $u1 from creatorid
ok ( $deleted, "ok to delete" );
