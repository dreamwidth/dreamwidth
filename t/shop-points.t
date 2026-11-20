#!/usr/bin/perl
#
# t/shop-points.t
#
# Point purchase and gift tests.
#
# Authors:
#     Alex
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

use DW::Shop::Cart;
use DW::Shop::Item::Points;

local $LJ::SHOP{points} = [];
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;

my $buyer     = temp_user();
my $recipient = temp_user();
my $balance   = $recipient->shop_points;
my $cart      = DW::Shop::Cart->new_cart($buyer) or BAIL_OUT('Could not create buyer cart');
my $cartid    = $cart->id;

END {
    LJ::get_db_writer()->do( 'DELETE FROM shop_carts WHERE cartid = ?', undef, $cartid )
        if $cartid;
}

my @mail;
local *LJ::send_mail;
*LJ::send_mail = sub { push @mail, $_[0]; return 1; };

for my $anonymous ( 1, 0 ) {
    subtest $anonymous ? 'anonymous gift' : 'named gift' => sub {
        my $item = DW::Shop::Item::Points->new(
            target_userid => $recipient->id,
            from_userid   => $buyer->id,
            points        => 30,
            anonymous     => $anonymous,
        );
        my ( $added, $error ) = $cart->add_item($item);
        ok( $added, 'gift can be added to the cart' ) or diag $error;
        return unless $added;

        my $order     = DW::Shop::Cart->get_from_cartid($cartid);
        my $purchased = $order->get_item( $item->id );
        is( $order->userid,          $buyer->id, 'order retains the buyer for payment lookup' );
        is( $purchased->from_userid, $buyer->id, 'stored item retains the sender for auditing' );
        is( $purchased->anonymous,   $anonymous, 'stored item retains the gift anonymity choice' );

        my $buyer_name = $buyer->display_name;
        my $buyer_user = $buyer->user;
        if ($anonymous) {
            like( $purchased->from_text, qr/anonymous/i,
                'text display labels the sender anonymous' );
            unlike( $purchased->from_html, qr/\Q$buyer_user\E/i,
                'HTML does not identify the sender' );
        }
        else {
            is( $purchased->from_text, $buyer_name, 'text display identifies a named sender' );
            like( $purchased->from_html, qr/\Q$buyer_user\E/i, 'HTML identifies a named sender' );
        }

        @mail = ();
        ok( $purchased->apply, 'delivery succeeds' );
        $balance += 30;
        is( $recipient->shop_points, $balance,              'recipient is credited 30 points' );
        is( scalar @mail,            1,                     'one gift notice is sent' ) or return;
        is( $mail[0]{to},            $recipient->email_raw, 'gift notice goes to the recipient' );
        like( $mail[0]{body}, qr/\b30\b/, 'gift notice includes the point amount' );
        if ($anonymous) {
            like( $mail[0]{body}, qr/anonymous/i,
                'email tells the recipient the gift is anonymous' );
            unlike( $mail[0]{body}, qr/\Q$buyer_user\E/i, 'email does not identify the sender' );
        }
        else {
            like( $mail[0]{body}, qr/\Q$buyer_name\E/, 'email identifies a named sender' );
        }
    };
}

subtest 'self-purchase' => sub {
    my $error;
    my %purchase  = ( target_userid => $buyer->id, from_userid => $buyer->id, points => 30 );
    my $anonymous = DW::Shop::Item::Points->new( %purchase, anonymous => 1 );
    ok( !$anonymous->can_be_added( errref => \$error ), 'anonymous self-purchase is rejected' );
    like( $error // '', qr/anonymous/i, 'error explains the restriction' );

    my $named = DW::Shop::Item::Points->new(%purchase);
    ok( $named->can_be_added( errref => \$error ), 'ordinary self-purchase is still allowed' );
};

done_testing;
