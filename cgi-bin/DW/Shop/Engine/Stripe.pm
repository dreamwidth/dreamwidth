#!/usr/bin/perl
#
# DW::Shop::Engine::Stripe
#
# Interfaces to Stripe for processing payments.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Engine::Stripe;

use strict;
use Carp qw/ croak confess /;
use HTTP::Request::Common;
use LWP::UserAgent;
use URI::Escape;

use DW::Shop::Cart;
use LJ::JSON;

use base qw/ DW::Shop::Engine /;

# new( $cart )
#
# instantiates a new engine for the given cart
sub new {
    return bless { cart => $_[1] }, $_[0];
}

# _encode()
#
# encode for stripe's url form encoded API. why the heck can't I find a module that does
# this for me!?
sub _encode {
    my $data = $_[0];

    my $encode = sub {
        my ( $key, $val ) = @_;
        my @rvs;

        if ( ref $val eq 'ARRAY' ) {
            my $ct = 0;
            foreach my $item (@$val) {
                if ( ref $item eq 'HASH' ) {
                    foreach my $subkey ( keys %$item ) {
                        push @rvs,
                            uri_escape(qq{$key\[$ct][$subkey]}) . '='
                            . uri_escape( $item->{$subkey} );
                    }
                }
                elsif ( ref $item ) {
                    confess 'expected hashref or scalar';
                }
                else {
                    push @rvs, uri_escape(qq{$key\[$ct]}) . '=' . uri_escape($item);
                }
                $ct += 1;
            }
        }
        else {
            push @rvs, uri_escape($key) . '=' . uri_escape($val);
        }
        return join '&', @rvs;
    };

    return join '&', map { $encode->( $_, $data->{$_}, '' ) } keys %$data;
}

# _post()
sub _post {
    my ( $path, $data ) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent('Dreamwidth Payment API <accounts@dreamwidth.org>');

    return $ua->post(
        qq{https://api.stripe.com/v1/$path},
        Content        => _encode($data),
        Authorization  => qq|Bearer $LJ::STRIPE{api_key}|,
        'Content-Type' => 'application/x-www-form-urlencoded',
    );
}

# checkout_url()
#
# this is simple, send them to the page for entering their credit card information
sub checkout_url {
    my $self = $_[0];

    # make sure that the cart contains something that costs something.  since
    # this check should have been done above, we die hardcore here.
    my $cart = $self->cart;
    die "Constraints not met: cart && cart->has_items && cart->total_cash > 0.00.\n"
        unless $cart && $cart->has_items && $cart->total_cash > 0.00;

    # and, just in case something terrible happens, make sure our state is good
    die "Cart not in valid state!\n"
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # Create cart items for Striping
    my @items;
    foreach my $item ( @{ $cart->items } ) {
        push @items,
            {
            name     => $item->name_text,
            amount   => $item->paid_cash * 100,
            quantity => 1,
            currency => 'usd',
            };
    }

    # start a session for this user, then redirect and send them to the Stripe interface
    # to actually complete the payment
    my $res = _post(
        'checkout/sessions',
        {
            cancel_url           => "$LJ::SITEROOT/shop",
            success_url          => "$LJ::SITEROOT/shop/receipt?ordernum=" . $cart->ordernum,
            payment_method_types => ['card'],
            client_reference_id  => $cart->id,
            line_items           => \@items,
        }
    );

    if ( $res->is_success ) {
        my $obj = from_json( $res->decoded_content );
        $cart->state($DW::Shop::STATE_PEND_PAID);
        $cart->paymentmethod_metadata( session_id => $obj->{id} );
    }
    else {
        confess 'Failed to start Stripe checkout process.';
    }

    # return URL to cc entry
    return "$LJ::SITEROOT/shop/stripe-checkout?ordernum=" . $cart->ordernum;
}

# process an incoming webhook
sub process_webhook {
    my ( $class, $event ) = @_;

    if ( $event->{type} eq 'checkout.session.completed' ) {
        my $cartid = $event->{data}{object}{client_reference_id};
        return ( 400, 'Invalid client_reference_id (invalid/not provided).' )
            unless defined $cartid;
        $cartid += 0;

        my $cart = DW::Shop::Cart->get_from_cartid($cartid);
        return ( 400, 'Invalid client_reference_id (cart not found).' )
            unless defined $cart;

        my $engine = $class->new($cart);
        return ( 500, 'Unable to build engine.' )
            unless $engine;

        # This event should only be fired when the cart has been paid, and in
        # that case, we should move the cart along.
        if ( $cart->state == $DW::Shop::STATE_PEND_PAID ) {
            $cart->state($DW::Shop::STATE_PAID);

            # TODO: What if this fails? do we need to refund the user?
            $engine->try_capture_points;
        }

        return ( 200, 'I gotchu, Stripe. User is good!' );
    }

    return ( 400, 'Unsupported event.' );
}

# accessors
sub cart { $_[0]->{cart} }

1;
