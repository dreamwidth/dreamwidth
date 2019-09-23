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
            amount   => $item->cost_cash * 100,
            quantity => 1,
            currency => 'usd',
            };
    }

    # start a session for this user, then redirect and send them to the Stripe interface
    # to actually complete the payment
    my $res = _post(
        'checkout/sessions',
        {
            cancel_url           => "$LJ::SITEROOT/shop/cart",
            success_url          => "$LJ::SITEROOT/shop/cart",    # TODO: Fixme
            payment_method_types => ['card'],
            client_reference_id  => $cart->id,
            line_items           => \@items,
        }
    );

    if ( $res->is_success ) {
        my $obj = from_json( $res->decoded_content );
        $cart->paymentmethod_metadata( session_id => $obj->{id} );
    }
    else {
        confess 'Failed to start Stripe checkout process.';
    }

    # return URL to cc entry
    return "$LJ::SITEROOT/shop/stripe-checkout";
}

# try_capture( ...many values... )
#
# given an input of some values, try to capture funds from the processor.  this
# uses a hook so that local sites can implement their own payment processing
# logic...
#
# note that it is important that you don't actually save the credit card number
# anywhere on your servers unless you are doing PCI compliance.
#
# to repeat: DO NOT SAVE CREDIT CARD NUMBERS TO DISK.  well, at least not in
# the US.  if you're in another country, your own rules apply.
#
sub try_capture {
    my ( $self, %in ) = @_;

    die "Unable to capture funds: no credit card processor loaded.\n"
        unless LJ::Hooks::are_hooks('creditcard_try_capture');

    # first capture the points if we have any to do
    return ( 0, 'Failed to capture points to complete order.' )
        unless $self->try_capture_points;

    # this hook is supposed to try to capture the funds.  return value is a
    # list: ( $code, $message ).  code is one of 0 (declined), 1 (success).
    # message is optional and if saved will be recorded as the status message.
    my ( $res, $msg ) = LJ::Hooks::run_hook( creditcard_try_capture => ( $self, \%in ) );

    # if the capture failed, refund the points
    $self->refund_captured_points
        unless $res;

    # the person who called us is responsible for setting up cart and engine
    # status based on the results.  improvement: maybe move all that logic
    # up to here so the workers are really small?
    return ( $res, $msg );
}

# accessors
sub cart { $_[0]->{cart} }

1;
