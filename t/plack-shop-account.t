# t/plack-shop-account.t
#
# Verify that scheduled paid account time is reviewed before it enters the cart.
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
use HTML::Parser;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Shop::Cart;
use LJ::Session;
use LJ::Test qw(temp_user);
use LJ::UniqCookie;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::DISABLED{payments} = 0;
local $LJ::DISABLED{captcha}  = 1;
local $LJ::DOMAIN_SHOP        = '';
local $LJ::SHOPROOT           = '/shop';
local %LJ::SHOP = ( paid12 => [ 25, 12, 'paid', 250 ] );

my $url   = 'http://localhost/shop/account?for=new';
my $today = DateTime->today;
my $later = $today->clone->add( days => 365 )->ymd;
my $next  = $today->clone->add( days => 1 )->ymd;
my $past  = $today->clone->subtract( days => 1 )->ymd;
my $email = 'paid-time-gift@example.org';

sub order_inputs {
    my ($html) = @_;
    my ( @forms, $form );
    my $parser = HTML::Parser->new( api_version => 3 );
    $parser->handler(
        start => sub {
            my ( $tag, $attrs ) = @_;
            if ( $tag eq 'form' ) {
                $form = {};
                push @forms, $form;
            }
            return unless $form && $attrs->{name} && ( $tag eq 'input' || $tag eq 'button' );
            return if ( $attrs->{type} // '' ) eq 'radio' && !exists $attrs->{checked};
            $form->{ $attrs->{name} } = $attrs;
        },
        'tagname, attr'
    );
    $parser->handler( end => sub { $form = undef if $_[0] eq 'form'; }, 'tagname' );
    $parser->parse($html);
    $parser->eof;
    my ($order) = grep { exists $_->{deliverydate} } @forms;
    return $order || {};
}

sub review_submission {
    my ( $form, $button ) = @_;
    return map { $_ => $form->{$_}{value} }
        grep   { $_ eq $button || ( $form->{$_}{type} // '' ) eq 'hidden' } keys %$form;
}

sub cart_items {
    my $dbh = LJ::get_db_writer();
    my ($cartid) =
        $dbh->selectrow_array( 'SELECT cartid FROM shop_carts WHERE uniq = ? ORDER BY cartid DESC',
        undef, LJ::UniqCookie->current_uniq );
    return $cartid ? DW::Shop::Cart->get_from_cartid($cartid)->items : [];
}

sub with_cart {
    my ( $client, $test, $order_url, %defaults ) = @_;
    $order_url //= $url;
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;

    my $form = $client->( GET $order_url );
    my $auth = order_inputs( $form->content )->{lj_form_auth}{value};
    ok( $auth, 'loaded the account purchase form' );

    my $post = sub {
        my ( $date, %overrides ) = @_;
        return $client->(
            POST $order_url,
            [
                %{
                    {
                        lj_form_auth => $auth,
                        accttype     => 'paid12',
                        email        => $email,
                        for          => 'new',
                        reason       => 'Enjoy your paid time!',
                        deliverydate => $date,
                        %defaults,
                        %overrides,
                    }
                }
            ]
        );
    };

    my $completed = eval { $test->($post); 1 };
    my $error     = $@;
    LJ::get_db_writer()
        ->do( 'DELETE FROM shop_carts WHERE uniq = ?', undef, $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ );
    die $error unless $completed;
}

test_psgi $app, sub {
    my $client = shift;

    subtest 'review then confirm a scheduled gift' => sub {
        with_cart $client, sub {
            my $post   = shift;
            my $review = $post->($later);
            is( $review->code, 200, 'shows review instead of redirecting to the cart' );
            like( $review->content, qr/\b365 days\b/, 'shows the calendar-day delay' );
            like( $review->content, qr/\Q$later\E/,   'shows the scheduled date' );
            is( scalar @{ cart_items() }, 0, 'review does not add paid time to the cart' );

            my $form    = order_inputs( $review->content );
            my $confirm = $form->{confirm_deliverydate}{value};
            ok( $confirm, 'offers a confirmation action for the reviewed date' );
            return unless $confirm;

            my $added =
                $client->( POST $url, [ review_submission( $form, 'confirm_deliverydate' ) ] );
            is( $added->header('Location'), '/shop', 'confirmed gift goes to the shop' );
            my $items = cart_items();
            is( scalar @$items, 1, 'adds one cart item' );
            is( $items->[0]->deliverydate, $later, 'persists the confirmed date' ) if @$items;
            is( $items->[0]->t_email,      $email, 'preserves the recipient' )     if @$items;
            is( $items->[0]->reason, 'Enjoy your paid time!', 'preserves the gift message' )
                if @$items;
        };
    };

    subtest 'edit or submit a changed date' => sub {
        with_cart $client, sub {
            my $post        = shift;
            my $review_form = order_inputs( $post->($later)->content );
            ok( $review_form->{edit_deliverydate}, 'offers Edit order on the review form' );
            my $edit =
                $client->( POST $url, [ review_submission( $review_form, 'edit_deliverydate' ) ] );
            my $form = order_inputs( $edit->content );
            is( $form->{deliverydate}{value}, $later,   'edit restores the delivery date' );
            is( $form->{email}{value},        $email,   'edit restores the recipient' );
            is( $form->{accttype}{value},     'paid12', 'edit restores the account type' );
            ok( !$form->{confirm_deliverydate}, 'edit returns to the purchase form' );
            is( scalar @{ cart_items() }, 0, 'editing does not add an item' );

            my %confirmation = review_submission( $review_form, 'confirm_deliverydate' );
            my %changed      = ( %confirmation, deliverydate => $next );
            my $review       = $client->( POST $url, [%changed] );
            is( $review->code, 200, 'old confirmation does not authorize a changed date' );
            like( $review->content, qr/\b1 day\b/, 'uses singular for tomorrow' );
            is( scalar @{ cart_items() }, 0, 'changed date has not been added' );

            $changed{confirm_deliverydate} = $next;
            $review = $client->( POST $url, [%changed] );
            is( $review->code, 200, 'matching an unreviewed date still requires review' );
            is( order_inputs( $review->content )->{confirm_deliverydate}{value},
                $next, 'offers confirmation for the newly submitted date' );
            is( scalar @{ cart_items() }, 0, 'matching unreviewed date has not been added' );
        };
    };

    subtest 'edit preserves the checked conversion for a signed-in buyer' => sub {
        my $buyer     = temp_user();
        my $other     = temp_user();
        my ($premium) = grep { $LJ::CAP{$_}{_account_type} eq 'premium' }
            keys %{ DW::Pay::all_shortnames() };
        my $expiry = time + 7 * 86400;
        DW::Pay::update_paid_status(
            $_,
            typeid     => $premium,
            expiretime => $expiry,
            permanent  => 0
            )
            or die DW::Pay::error_text()
            for ( $buyer, $other );

        my $session = LJ::Session->create( $buyer, exptype => 'short', nolog => 1 )
            or die 'Could not create a buyer session';
        my $cookie =
              'ljmastersession='
            . $session->master_cookie_string
            . '; ljloggedin='
            . $session->loggedin_cookie_string;
        my $signed_in = sub {
            my ($request) = @_;
            $request->header( Cookie => $cookie );
            return $client->($request);
        };
        my $gift_url = 'http://localhost/shop/account?for=gift';

        with_cart $signed_in, sub {
            my $post   = shift;
            my $prompt = order_inputs( $post->($later)->content );
            ok( $prompt->{prem_convert}, 'offers conversion for a premium recipient' ) or return;

            my $review = order_inputs(
                $post->( $later, prem_convert => $prompt->{prem_convert}{value} )->content );
            ok( $review->{edit_deliverydate}, 'checked conversion proceeds to delivery review' )
                or return;
            my $edit = $signed_in->(
                POST $gift_url,
                [ review_submission( $review, 'edit_deliverydate' ) ]
            );
            my $form = order_inputs( $edit->content );
            ok( $form->{prem_convert}, 'Edit order restores the conversion checkbox' ) or return;
            ok( exists $form->{prem_convert}{checked}, 'conversion is still checked' );
            is( scalar @{ cart_items() }, 0, 'editing the conversion does not add an item' );

            my @fields = (
                lj_form_auth => $form->{lj_form_auth}{value},
                prem_convert => $form->{prem_convert}{value}
            );
            my $changed =
                order_inputs( $post->( $later, @fields, username => $other->user )->content );
            ok(
                $changed->{prem_convert} && !exists $changed->{prem_convert}{checked},
                'a different premium recipient requires a new conversion choice'
            );

            my $unchanged = order_inputs( $post->( $later, @fields )->content );
            ok( $unchanged->{confirm_deliverydate},
                'unchanged conversion goes straight back to date review' )
                or return;
            my $added = $signed_in->(
                POST $gift_url,
                [ review_submission( $unchanged, 'confirm_deliverydate' ) ]
            );
            is( $added->header('Location'),
                '/shop', 'signed-in buyer can confirm the reviewed date' );
            my $items = cart_items();
            is( scalar @$items, 1, 'adds the reviewed conversion only' );
            is( $items->[0]->t_userid, $buyer->id, 'preserves the original recipient' ) if @$items;
            is( $items->[0]->from_userid, $buyer->id, 'records the signed-in buyer' ) if @$items;
            }, $gift_url,
            for      => 'gift',
            username => $buyer->user;
    };

    subtest 'past and same-day orders' => sub {
        with_cart $client, sub {
            my $post    = shift;
            my $invalid = $post->($past);
            like( $invalid->content, qr/time cannot be in the past/, 'past date remains invalid' );
            is( scalar @{ cart_items() }, 0, 'past date is not added' );

            my $immediate = $post->( $today->ymd );
            is( $immediate->header('Location'), '/shop', 'today does not require confirmation' );
            my $items = cart_items();
            is( scalar @$items,            1,     'adds the immediate order' );
            is( $items->[0]->deliverydate, undef, 'today is not persisted as a schedule' )
                if @$items;
        };
    };
};

done_testing();
