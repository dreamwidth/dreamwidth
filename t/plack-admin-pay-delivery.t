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
use DW::RenameToken;
use DW::Shop::Cart;
use DW::Shop::Engine::Stripe;
use DW::Shop::Item::Account;
use DW::Shop::Item::Rename;
use DW::User::Rename;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'testDeliveryXYZ';
local $LJ::T_SUPPRESS_EMAIL           = 1;
local $LJ::DISABLED{payments}         = 0;
local $LJ::DOMAIN_SHOP                = 'localhost';
local $LJ::SITEADDRESS                = '123 Test Street';
local $LJ::SHOP{paid1}  = [ 3,  1, 'paid',   30 ];
local $LJ::SHOP{rename} = [ 15, 0, 'rename', 150 ];

my $buyer = temp_user();
$buyer->set_email('buyer@example.test');
my $buyer_name = $buyer->user;
my $admin      = temp_user();
my $other      = temp_user();
my @cartids;
my $audit_constraint;

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
        my $item =
            ref $args eq 'HASH'
            ? DW::Shop::Item::Account->new(
            type          => 'paid1',
            from_userid   => $buyer->id,
            target_userid => temp_user()->id,
            %$args,
            )
            : $args;
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
    $dbh->do("ALTER TABLE statushistory DROP CHECK $audit_constraint") if $audit_constraint;
    for my $cartid (@cartids) {
        $dbh->do( 'DELETE FROM renames WHERE cartid = ?',    undef, $cartid );
        $dbh->do( 'DELETE FROM shop_cmo WHERE cartid = ?',   undef, $cartid );
        $dbh->do( 'DELETE FROM shop_carts WHERE cartid = ?', undef, $cartid );
        $dbh->do( 'DELETE FROM statushistory WHERE adminid = ? AND notes LIKE ?',
            undef, $admin->id, "%Order #$cartid,%" );
    }
    my $old_buyer = LJ::load_user($buyer_name);
    $old_buyer->delete_and_purge_completely if $old_buyer && $old_buyer->id != $buyer->id;
}

with_fake_memcache {
    my $rename = DW::Shop::Item::Rename->new(
        from_userid   => $buyer->id,
        target_userid => $buyer->id
    );
    my $paid = make_cart(
        $DW::Shop::STATE_PEND_PAID,
        { deliverydate => $original },
        { deliverydate => $original },
        {},
        { deliverydate => $past },
        { deliverydate => $original }, $rename,
    );
    my ( $scheduled, $untouched, $immediate, $overdue, $applied ) = @{ $paid->items };
    $applied->{applied} = 1;
    $paid->paymentmethod('stripe');
    my $delivered = make_cart( $DW::Shop::STATE_PROCESSED, { deliverydate => $original } );
    my $unpaid    = make_cart( $DW::Shop::STATE_CHECKOUT,  { deliverydate => $original } );
    my $refunded  = make_cart( $DW::Shop::STATE_REFUNDED,  { deliverydate => $original } );
    my $ambiguous = make_cart( $DW::Shop::STATE_PAID,      { deliverydate => $original }, {} );
    my ( $first, $second ) = @{ $ambiguous->items };
    $second->id( $first->id );
    $ambiguous->save or BAIL_OUT('Could not save duplicate item IDs');
    my $cartid            = $paid->id;
    my $itemid            = $scheduled->id;
    my $dbh               = LJ::get_db_writer();
    my $stripe_completion = {
        type => 'checkout.session.completed',
        data => { object => { client_reference_id => $cartid } },
    };
    {
        my $lock = DW::Shop::Cart->processing_lock($cartid)
            or BAIL_OUT('Could not lock pending Stripe cart');
        my ($status) = DW::Shop::Engine::Stripe->process_webhook($stripe_completion);
        is( $status, 503, 'Stripe must retry a locked checkout completion' );
        is( DW::Shop::Cart->get_from_cartid($cartid)->state,
            $DW::Shop::STATE_PEND_PAID, 'locked completion leaves the cart pending' );
        is( stored_date( $cartid, $itemid ), $original,
            'locked completion leaves items unchanged' );
    }
    my ($stripe_status) = DW::Shop::Engine::Stripe->process_webhook($stripe_completion);
    is( $stripe_status, 200, 'Stripe can complete payment after the lock is released' );
    is( DW::Shop::Cart->get_from_cartid($cartid)->state,
        $DW::Shop::STATE_PAID, 'unlocked completion marks the cart paid' );
    my $nextscan = time + 7200;
    $dbh->do( 'UPDATE shop_carts SET nextscan = ? WHERE cartid = ?', undef, $nextscan, $cartid )
        or BAIL_OUT( $dbh->errstr );
    my $stored_nextscan = sub {
        return $dbh->selectrow_array( 'SELECT nextscan FROM shop_carts WHERE cartid = ?',
            undef, $cartid );
    };
    my $audit_notes = sub {
        return $dbh->selectrow_array(
            'SELECT notes FROM statushistory WHERE userid = ? AND adminid = ? AND shtype = ?',
            undef, $scheduled->t_userid, $admin->id, 'paidstatus' );
    };

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

        my $cmo = make_cart( $DW::Shop::STATE_CHECKOUT, { deliverydate => $original } );
        $cmo->paymentmethod('checkmoneyorder');
        my $cmo_id = $cmo->id;
        my $confirm_url =
            'http://localhost/shop/confirm?ordernum=' . $cmo->ordernum . '&as=' . $buyer->user;
        my $confirm_cmo = sub {
            return $request->( POST $confirm_url, [ lj_form_auth => form_auth($buyer) ] );
        };
        my $record_cmo = sub {
            return $request->(
                POST $url . $cmo_id . '&as=' . $admin->user,
                [
                    record_cmo    => 1,
                    paymentmethod => 'cash',
                    lj_form_auth  => form_auth($admin),
                ]
            );
        };
        {
            my $lock = DW::Shop::Cart->processing_lock($cmo_id)
                or BAIL_OUT('Could not lock check or money order cart');
            $confirm_cmo->();
            my $stored = DW::Shop::Cart->get_from_cartid($cmo_id);
            is( $stored->state, $DW::Shop::STATE_CHECKOUT,
                'locked confirmation does not advance checkout' );
            is( $stored->email, undef, 'locked confirmation does not save email' );
        }
        $confirm_cmo->();
        is( DW::Shop::Cart->get_from_cartid($cmo_id)->state,
            $DW::Shop::STATE_PEND_PAID, 'unlocked confirmation makes the order pending payment' );
        {
            my $lock = DW::Shop::Cart->processing_lock($cmo_id)
                or BAIL_OUT('Could not lock pending check or money order cart');
            $record_cmo->();
            is( DW::Shop::Cart->get_from_cartid($cmo_id)->state,
                $DW::Shop::STATE_PEND_PAID, 'locked receipt does not mark the order paid' );
            is(
                $dbh->selectrow_array(
                    'SELECT paymentmethod FROM shop_cmo WHERE cartid = ?',
                    undef, $cmo_id
                ),
                undef,
                'locked receipt does not record a payment'
            );
        }
        my $receipt = $record_cmo->();
        like(
            $receipt->header('Location') // '',
            qr{/admin/pay/view\?cartid=$cmo_id\z},
            'unlocked receipt redirects to the order'
        );
        is( DW::Shop::Cart->get_from_cartid($cmo_id)->state,
            $DW::Shop::STATE_PAID, 'unlocked receipt marks the order paid' );

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

        for my $invalid ( '', 'tomorrow', '2031-02-29', '2032-02-30', "${new_date}junk", $past,
            $today )
        {
            my $res = $post->( $admin, deliverydate => $invalid );
            like( $res->content, qr/valid future delivery date/i, "rejects date '$invalid'" );
        }
        for my $item ( $immediate, $overdue, $applied, $rename, $delivered->items->[0] ) {
            my $res = $post->( $admin, itemid => $item->id );
            like( $res->content, qr/no longer eligible/i, 'rejects ineligible or foreign item' );
        }
        for my $cart ( $delivered, $unpaid, $refunded ) {
            my $res = $post->( $admin, cartid => $cart->id, itemid => $cart->items->[0]->id );
            like( $res->content, qr/no longer eligible/i, 'rejects a non-pending paid order' );
        }
        my $duplicate_result = $post->( $admin, cartid => $ambiguous->id, itemid => $first->id );
        like( $duplicate_result->content, qr/no longer eligible/i, 'rejects an ambiguous item ID' );
        is( stored_date( $cartid, $itemid ), $original, 'invalid submissions do not save' );

        my $paid_rename = DW::Shop::Cart->get_from_cartid($cartid)->get_item( $rename->id );
        my $token       = DW::RenameToken->new( token => $paid_rename->token )
            or BAIL_OUT('Could not load cart rename token');
        my $new_username = $buyer_name . '_renamed';
        {
            my $lock = DW::Shop::Cart->processing_lock($cartid)
                or BAIL_OUT('Could not take fixture processing lock');
            like(
                $post->($admin)->content,
                qr/order is busy/i,
                'does not reschedule a locked cart'
            );
            ok( !$buyer->rename( $new_username, token => $token ),
                'rename defers on the same lock' );
            is(
                $dbh->selectrow_array(
                    'SELECT user FROM user WHERE userid = ?', undef, $buyer->id
                ),
                $buyer_name,
                'lock contention leaves the username unchanged'
            );
            is(
                $dbh->selectrow_array(
                    'SELECT status FROM renames WHERE renid = ?',
                    undef, $token->id
                ),
                'U',
                'lock contention does not consume the token'
            );
            is( stored_date( $cartid, $itemid ),
                $original, 'lock contention leaves the date unchanged' );
        }

        my $admin_id   = $admin->id;
        my $constraint = "test_delivery_audit_$admin_id";
        my $recipient  = $scheduled->t_userid;
        $dbh->do( "ALTER TABLE statushistory ADD CONSTRAINT $constraint "
                . "CHECK (adminid <> $admin_id OR userid <> $recipient)" )
            or BAIL_OUT( $dbh->errstr );
        $audit_constraint = $constraint;
        my $audit_failed = $post->($admin);
        $dbh->do("ALTER TABLE statushistory DROP CHECK $audit_constraint")
            or BAIL_OUT( $dbh->errstr );
        undef $audit_constraint;
        ok(
            !defined $audit_failed->header('Location'),
            'audit failure does not redirect as success'
        );
        like(
            $audit_failed->content,
            qr/unable to save the delivery date/i,
            'audit failure is shown'
        );
        is( stored_date( $cartid, $itemid ), $original, 'failed audit rolls back the new date' );
        is( $audit_notes->(), undef, 'failed audit leaves no history row' );

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
        ok( !$updated->get_item($itemid)->applied,        'rescheduling does not apply the item' );
        ok( !$updated->get_item( $overdue->id )->applied, 'unrelated due item stays pending' );
        is( $stored_nextscan->(), $nextscan, 'rescheduling does not shorten the retry backoff' );
        my $history = $audit_notes->();
        like(
            $history // '',
            qr/\Q$original\E.*\Q$new_date\E/,
            'audit log records old and new dates'
        );

        my ($duplicate_status) = DW::Shop::Engine::Stripe->process_webhook($stripe_completion);
        is( $duplicate_status, 200, 'Stripe acknowledges an already processed completion' );
        is( stored_date( $cartid, $itemid ),
            $new_date, 'duplicate completion preserves the new date' );
        is( $audit_notes->(),     $history,  'duplicate completion preserves the audit row' );
        is( $stored_nextscan->(), $nextscan, 'duplicate completion preserves the retry backoff' );

        ok(
            $buyer->rename( $new_username, token => $token ),
            'rename can retry after rescheduling'
        );
        my $redeemed = DW::Shop::Cart->get_from_cartid($cartid);
        ok(
            $redeemed->get_item( $rename->id )->applied,
            'rename redemption updates the mixed cart'
        );
        is( $redeemed->get_item($itemid)->deliverydate,
            $new_date, 'rename preserves the saved delivery date' );
        is( $stored_nextscan->(), $nextscan, 'rename does not shorten the retry backoff either' );
    };
};

done_testing;
