#!/usr/bin/perl
#
# DW::Hooks::HolidayPromotion
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

package DW::Hooks::HolidayPromotion;

use strict;
use LJ::Hooks;

# promotion HTML
LJ::Hooks::register_hook( 'shop_cart_status_bar', sub {
    my ( $shop, $cart, $retref ) = @_;

    # anonymous sessions can't benefit from the promotion
    return if $shop->anonymous;

    # bail out if it's expired (2010-01-01 00:00:00)
    return if time > 1262304000;

    # put the note up top so people know
    $$retref = "<div class='shop-error'><strong>" . BML::ml( 'shop.holidaypromoblurb' ) .
               "</strong></div>\n" . $$retref;
} );

# hook to add a new item when they purchase somethign eligibile
LJ::Hooks::register_hook( 'shop_cart_added_item', sub {
    my ( $cart, $item ) = @_;

    # bail out if it's expired (2010-01-01 00:00:00)
    return if time > 1262304000;

    # ignore promo linked items so we don't loop forever
    return if $item->{_holiday_promo_2009};

    # validation checks
    return unless $cart->userid;
    return if $item->t_userid && $item->t_userid == $cart->userid;
    return if $item->permanent || $item->months < 6;

    # determine what kind of time to give the user.  rules are simple, if
    # the user has premium, give them premium.  else, they get paid.
    my $type = DW::Pay::get_account_type( $cart->userid );
    $type = 'paid' if $type ne 'premium';

    # looks good, build a new object and stick it on the cart
    my $new = bless {
        cost   => 0.00,
        months => int( $item->months / 6 ) * 2,
        class  => $type,
        target_userid => $cart->userid,
        cannot_conflict => 1,
        noremove => 1,
        from_name => $LJ::SITENAME,

        _holiday_promo_2009  => $item->id,
    }, 'DW::Shop::Item::Account';

    my ( $rv, $msg ) = $cart->add_item( $new );
    warn "Failed to add holiday promotion time: $msg\n"
        unless $rv;
} );

# when they remove an item ...
LJ::Hooks::register_hook( 'shop_cart_removed_item', sub {
    my ( $cart, $item ) = @_;

    # don't do anything if we're removing a promo item
    return if $item->{_holiday_promo_2009};

    # iterate over the cart to see if any items link to this one
    foreach my $it ( @{$cart->items} ) {
        if ( $it->{_holiday_promo_2009} == $item->id ) {
            # they're linked, remove it forcefully (mental image: large hammer)
            $cart->remove_item( $it->id, force => 1 );
        }
    }

} );


1;
