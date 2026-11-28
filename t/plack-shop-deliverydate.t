#!/usr/bin/perl
#
# t/plack-shop-deliverydate.t
#
# Test delivery dates on new and existing shop items.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use DateTime;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Shop;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::DISABLED{payments} = 0;
local $LJ::DOMAIN_SHOP        = '';
local $LJ::SHOPROOT           = '/shop';
local $LJ::SHOP_CMO_MINIMUM   = 0;
local $LJ::T_SUPPRESS_EMAIL   = 1;
local %LJ::SHOP               = (
    paid1  => [ 3,  1,     'paid', 30 ],
    rename => [ 15, undef, undef,  150 ],
);

my $recipient   = temp_user();
my $today       = DateTime->today;
my $future_date = $today->clone->add( days => 7 )->ymd;
my $past_date   = $today->clone->subtract( days => 1 )->ymd;
my $shop_url    = 'http://localhost/shop';

test_psgi $app, sub {
    my $request = shift;

    for my $purchase (
        [ account => 'Account', $future_date, 'future' ],
        [ renames => 'Rename',  $future_date, 'future' ],
        [ account => 'Account', $past_date,   'past' ],
        [ renames => 'Rename',  $past_date,   'past' ],
        )
    {
        my ( $page, $class, $submitted_date, $when ) = @$purchase;
        my $url = "$shop_url/$page?for=gift";

        subtest "$page gift purchase with a $when delivery date" => sub {
            local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
            my $cart_id = DW::Shop->get->cart->id;
            my $form    = $request->( GET $url );
            is( $form->code, 200, 'gift form renders' );
            unlike(
                $form->content,
                qr/<input\b[^>]*\bname=["']deliverydate["']/i,
                'gift form does not offer a delivery date'
            );

            my ($token) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            ok( $token, 'gift form contains a form auth token' );
            my $response = $request->(
                POST $url,
                [
                    lj_form_auth => $token,
                    for          => 'gift',
                    username     => $recipient->user,
                    deliverydate => $submitted_date,
                    $page eq 'account' ? ( accttype => 'paid1' ) : ( item => 'rename' ),
                ]
            );
            is( $response->code,               303,     'gift is added successfully' );
            is( $response->header('Location'), '/shop', 'successful POST returns to the shop' );

            my $items = DW::Shop::Cart->get_from_cartid($cart_id)->items;
            is( scalar @$items, 1, 'one item is saved in the cart' );
            my ($item) = @$items;
            isa_ok( $item, "DW::Shop::Item::$class", 'saved item' );
            is( $item && $item->t_userid, $recipient->id,
                'saved gift has the requested recipient' );
            ok( $item && !defined $item->deliverydate, 'saved gift has no delivery date' );
        };
    }

    subtest 'existing scheduled item' => sub {
        local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
        my $cart        = DW::Shop->get->cart;
        my %gift        = ( target_userid => $recipient->id, from_userid => 0, anonymous => 1 );
        my $future_gift = DW::Shop::Item::Rename->new( %gift, deliverydate => $future_date );
        my ($added)     = $cart->add_item($future_gift);
        ok( $added, 'legacy scheduled item can be stored' );

        my ($saved) = @{ DW::Shop::Cart->get_from_cartid( $cart->id )->items };
        is( $saved->deliverydate, $future_date, 'delivery date survives storage and reload' );
        ok( !$saved->apply && !$saved->applied, 'scheduled item does not apply before its date' );

        my $cart_page = $request->( GET "$shop_url/cart" );
        is( $cart_page->code, 200, 'cart renders with the scheduled gift' );
        like( $cart_page->content, qr/>\s*\Q$future_date\E\s*</, 'cart shows the scheduled date' );

        my $due_gift = DW::Shop::Item::Rename->new( %gift, deliverydate => $past_date );
        ok( $due_gift->apply && $due_gift->applied,
            'item can apply once its delivery date passes' );
    };
};

done_testing();
