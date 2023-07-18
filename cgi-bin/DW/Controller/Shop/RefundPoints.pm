#!/usr/bin/perl
#
# DW::Controller::Shop::RefundPoints
#
# This controller handles when someone wants to refund their account back to points
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop::RefundPoints;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;

DW::Routing->register_string( '/shop/refundtopoints', \&shop_refund_to_points_handler, app => 1 );

sub shop_refund_to_points_handler {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( form_auth => 1 );
    return $rv unless $ok;

    $rv->{status}     = DW::Pay::get_paid_status( $rv->{remote} );
    $rv->{rate}       = DW::Pay::get_refund_points_rate( $rv->{remote} );
    $rv->{type}       = DW::Pay::get_account_type_name( $rv->{remote} );
    $rv->{can_refund} = DW::Pay::can_refund_points( $rv->{remote} );

    if ( $rv->{can_refund} && ref $rv->{status} eq 'HASH' && $rv->{rate} > 0 ) {
        $rv->{blocks} = int( $rv->{status}->{expiresin} / ( 86400 * 30 ) );
        $rv->{days}   = $rv->{blocks} * 30;
        $rv->{points} = $rv->{blocks} * $rv->{rate};
    }

    unless ( $rv->{can_refund} ) {

        # tell them how long they have to wait for their next refund.
        my $last = $rv->{remote}->prop("shop_refund_time");
        $rv->{next_refund} = LJ::mysql_date( $last + 86400 * 30 ) if $last;
    }

    my $r = DW::Request->get;
    return DW::Template->render_template( 'shop/refundtopoints.tt', $rv )
        unless $r->did_post && $rv->{can_refund};

    # User posted, so let's refund them if we can.
    die "Should never get here in a normal flow.\n"
        unless $rv->{points} > 0;

    # This should never expire the user. Let's sanity check that though, and
    # error if they're within 5 minutes of 30 day boundary.
    my $expiretime = $rv->{status}->{expiretime} - ( $rv->{days} * 86400 );
    die "Your account is just under 30 days and can't be converted.\n"
        if $expiretime - time() < 300;

    $rv->{remote}->give_shop_points(
        amount => $rv->{points},
        reason => sprintf( 'refund %d days of %s time', $rv->{days}, $rv->{type} )
    ) or die "Failed to refund points.\n";
    $rv->{remote}->set_prop( "shop_refund_time", time() );
    DW::Pay::update_paid_status( $rv->{remote},
        expiretime => $rv->{status}->{expiretime} - ( $rv->{days} * 86400 ) );

    # This is a hack, so that when the user lands on the page that says they
    # were successful, it updates the number of points they have. It's just a nice
    # visual indicator of success.
    $rv->{shop} = DW::Shop->get;
    $rv->{cart} =
        $r->get_args->{newcart} ? DW::Shop::Cart->new_cart( $rv->{u} ) : $rv->{shop}->cart;
    $rv->{cart_display} = DW::Template->template_string( 'shop/cartdisplay.tt', $rv );

    # Return the OK to the user.
    $rv->{refunded} = 1;
    return DW::Template->render_template( 'shop/refundtopoints.tt', $rv );
}

1;
