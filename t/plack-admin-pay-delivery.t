# t/plack-admin-pay-delivery.t
#
# Test changes to scheduled shop deliveries on the payment admin page.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use DateTime;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use DW::Shop::Cart;
use DW::Shop::Item::Account;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'testDeliveryXYZ';
local $LJ::T_SUPPRESS_EMAIL           = 1;
local $LJ::SHOP{paid1} = [ 3, 1, 'paid', 30 ];

my $buyer = temp_user();
my $admin = temp_user();
my $other = temp_user();
my @cartids;

ok( $admin->grant_priv('payments'), 'granted payments privilege' );
ok( $other->grant_priv( 'siteadmin', 'theschwartz' ), 'granted unrelated privilege' );

my $today    = LJ::mysql_date();
my $original = DateTime->now( time_zone => 'local' )->add( days => 30 )->ymd;
my $new_date = DateTime->now( time_zone => 'local' )->add( days => 45 )->ymd;
my $past     = DateTime->now( time_zone => 'local' )->subtract( days => 1 )->ymd;

sub make_cart {
    my ( $state, @items ) = @_;
    my $cart = DW::Shop::Cart->new_cart($buyer);
    push @cartids, $cart->id;
    for my $args (@items) {
        my $item = DW::Shop::Item::Account->new(
            type          => 'paid1',
            from_userid   => $buyer->id,
            target_userid => temp_user()->id,
            %$args,
        );
        my ( $added, $error ) = $cart->add_item($item);
        BAIL_OUT("Could not add fixture item: $error") unless $added;
    }
    $cart->state($state);
    return $cart;
}

sub form_auth {
    my ($user) = @_;
    LJ::set_remote($user);
    delete $LJ::REQ_GLOBAL{form_auth_chal};
    my $token = LJ::form_auth(1);
    LJ::set_remote(undef);
    return $token;
}

sub stored_date {
    my ( $cartid, $itemid ) = @_;
    return DW::Shop::Cart->get_from_cartid($cartid)->get_item($itemid)->deliverydate;
}

END {
    my $dbh = LJ::get_db_writer();
    for my $cartid (@cartids) {
        $dbh->do( 'DELETE FROM shop_carts WHERE cartid = ?', undef, $cartid );
        $dbh->do( 'DELETE FROM statushistory WHERE adminid = ? AND notes LIKE ?',
            undef, $admin->id, "%Order #$cartid,%" );
    }
}

with_fake_memcache {
    my $paid = make_cart(
        $DW::Shop::STATE_PAID,
        { deliverydate => $original },
        { deliverydate => $original },
        {}, { deliverydate => $past },
    );
    my ( $scheduled, $untouched, $immediate, $overdue ) = @{ $paid->items };
    my $delivered = make_cart( $DW::Shop::STATE_PROCESSED, { deliverydate => $original } );
    my $unpaid    = make_cart( $DW::Shop::STATE_CHECKOUT,  { deliverydate => $original } );
    my $cartid    = $paid->id;
    my $itemid    = $scheduled->id;

    test_psgi $app, sub {
        my ($request) = @_;
        my $url       = 'http://localhost/admin/pay/view?cartid=';
        my $admin_url = $url . $cartid . '&as=' . $admin->user;
        my $post      = sub {
            my ( $user, %override ) = @_;
            my $target = delete $override{cartid} // $cartid;
            my $token  = delete $override{token}  // form_auth($user);
            my %fields = (
                adjust_delivery => 1,
                itemid          => $itemid,
                deliverydate    => $new_date,
                %override,
                lj_form_auth => $token,
            );
            my $action = $url . $target . '&as=' . ( $user ? $user->user : 'nobody_exists' );
            return $request->( POST $action, [%fields] );
        };

        my $page = $request->( GET $admin_url );
        is( $page->code, 200, 'payments administrator can inspect order' );
        my @controls = $page->content =~ /name="adjust_delivery"/g;
        is( scalar @controls, 2, 'only future scheduled items have edit controls' );

        my $logged_out = $post->( undef, token => 'invalid' );
        like( $logged_out->header('Location') // '',
            qr{/login\?}, 'logged-out POST requires login' );
        like(
            $post->($other)->content,
            qr/necessary privilege.*payments/s,
            'unrelated administrator cannot reschedule'
        );
        like(
            $post->( $admin, token => 'invalid' )->content,
            qr/Invalid form submission/i,
            'administrator needs a valid CSRF token'
        );
        $request->( GET "$admin_url&adjust_delivery=1&itemid=$itemid&deliverydate=$new_date" );
        is( stored_date( $cartid, $itemid ), $original, 'refused requests and GET do not save' );

        for my $invalid ( '', 'tomorrow', '2032-02-30', "${new_date}junk", $past, $today ) {
            my $res = $post->( $admin, deliverydate => $invalid );
            like( $res->content, qr/valid future delivery date/i, "rejects date '$invalid'" );
        }
        for my $item ( $immediate, $overdue, $delivered->items->[0] ) {
            my $res = $post->( $admin, itemid => $item->id );
            like( $res->content, qr/no longer eligible/i, 'rejects ineligible or foreign item' );
        }
        for my $cart ( $delivered, $unpaid ) {
            my $res = $post->( $admin, cartid => $cart->id, itemid => $cart->items->[0]->id );
            like( $res->content, qr/no longer eligible/i, 'rejects a non-pending paid order' );
        }
        is( stored_date( $cartid, $itemid ), $original, 'invalid submissions do not save' );

        my $result = $post->($admin);
        like(
            $result->header('Location') // '',
            qr{/admin/pay/view\?cartid=$cartid\z},
            'successful POST redirects back to this order'
        );
        is( stored_date( $cartid, $itemid ), $new_date, 'new date persists to the order' );
        is( stored_date( $cartid, $untouched->id ), $original,
            'other scheduled item is unchanged' );
        my $updated = DW::Shop::Cart->get_from_cartid($cartid);
        is( $updated->state, $DW::Shop::STATE_PAID, 'the order remains paid and pending delivery' );
        ok( !$updated->get_item($itemid)->applied, 'rescheduling does not apply the item' );
        my $history =
            LJ::get_db_writer()
            ->selectrow_array(
            'SELECT notes FROM statushistory WHERE userid = ? AND adminid = ? AND shtype = ?',
            undef, $scheduled->t_userid, $admin->id, 'paidstatus', );
        like(
            $history // '',
            qr/\Q$original\E.*\Q$new_date\E/,
            'audit log records old and new dates'
        );
    };
};

done_testing;
