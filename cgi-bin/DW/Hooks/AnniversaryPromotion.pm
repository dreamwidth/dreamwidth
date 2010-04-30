#!/usr/bin/perl
#
# DW::Hooks::AnniversaryPromotion
#
# This file explains Dreamwidth's plans for world domination. Be sure to keep it updated!
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Hooks::AnniversasryPromotion;

use strict;
use LJ::Hooks;


# returns if the promotion is valid right now
sub promo_valid {
    # valid from 2010-05-01 01:00:00 UTC to 2010-05-08 01:00:00 UTC
    # this corresponds to 2010-04-30 21:00:00 EDT and a week later...
    return 0 if time < 1272675600 || time > 1273280400;
    return 1;
}


# returns how many points this cart is eligible for
sub cart_bonus_points {
    return int( $_[0]->total_cash );
}


# promotion HTML
LJ::Hooks::register_hook( 'shop_controller', sub {
    my ( $rv ) = @_;

    # ensure we're a valid promotional period and not anon
    return unless promo_valid();
    return if $rv->{shop}->anonymous;

    # put the note up top so people know
    $rv->{cart_display} .=
        "<div class='shop-error'><strong>" .
        LJ::Lang::ml( 'shop.anniversarypromoblurb' ) .
        "</strong></div>\n";
} );


# put information after the cart is rendered
LJ::Hooks::register_hook( 'shop_cart_render', sub {
    my ( $retref, %opts ) = @_;
    return if $opts{admin};

    # promo period and not anonymous
    return unless promo_valid();
    return unless $opts{cart}->userid;

    # determine how many points they get ... basically, 1 point per $1 USD
    # spent..  does not get points for spending points!
    my $points = cart_bonus_points( $opts{cart} );

    # text depends on how many points they get
    $$retref .= '<p class="shop-account-status">';
    if ( $points > 0 ) {
        $$retref .= LJ::Lang::ml( 'shop.annivpromo.points', { points => $points } );
    } else {
        $$retref .= LJ::Lang::ml( 'shop.annivpromo.nopoints' );
    }
    $$retref .= '</p>';
} );


# this is where the magic happens.  when a cart enters or leaves the
# paid state, then we have to apply or unapply their bonus points.
LJ::Hooks::register_hook( 'shop_cart_state_change', sub {
    my ( $cart, $newstate ) = @_;

    # if the cart is going INTO the paid state, then we apply the bonus points
    # to the user who bought the items
    if ( $newstate == $DW::Shop::STATE_PAID ) {
        my $points = cart_bonus_points( $cart );
        my $u = LJ::load_userid( $cart->userid );
        return unless $points && $u;

        # now give them the points for their bonus
        $u->give_shop_points( amount => $points, reason => sprintf( 'order %d bonus points', $cart->id ) );
        return;
    }

    # however, if the OLD state was PROCESSED (means we're being refunded or
    # something is happening) then we need to email admins.  the logic to
    # determine if we ever gave the user bonus points is too fickle, for now
    # we can just handle point reversals manually.
    if ( $cart->state == $DW::Shop::STATE_PROCESSED ) {
        LJ::send_mail( {
            to => $LJ::ADMIN_EMAIL,
            from => $LJ::BOGUS_EMAIL,
            fromname => $LJ::SITENAME,
            subject => 'Attention: Order Investigation Needed',
            body => <<EOF,
Dear admins,

Order #@{[$cart->id]} has left the PROCESSED state during an active promotion
period and needs to be investigated.  The user may need to have bonus points
unapplied from their account.


Best regards,
The $LJ::SITENAMESHORT Payment System
EOF
        } );
    }

} );


1;
