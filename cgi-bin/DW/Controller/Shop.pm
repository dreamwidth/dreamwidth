#!/usr/bin/perl
#
# DW::Controller::Shop
#
# This controller is for shop handlers.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Shop;
use JSON;

# routing directions
DW::Routing->register_string( '/shop', \&shop_index_handler, app => 1 );
DW::Routing->register_string( '/shop/points', \&shop_points_handler, app => 1 );

# our basic shop controller, this does setup that is unique to all shop
# pages and everybody should call this first.  returns the same tuple as
# the controller method.
sub _shop_controller {
    my %args = ( @_ );
    my $r = DW::Request->get;

    # if payments are disabled, do nothing
    unless ( LJ::is_enabled( 'payments' ) ) {
        $r->redirect( "$LJ::SITEROOT/" );
        return ( 0, 'The shop is currently disabled.' );
    }

    # if they're banned ...
    my $err = DW::Shop->remote_sysban_check;
    return ( 0, $err ) if $err;

    # basic controller setup
    my ( $ok, $rv ) = controller( %args );
    return ( $ok, $rv ) unless $ok;

    # the entire shop uses these files
    LJ::need_res( 'stc/shop.css' );
    LJ::set_active_resource_group( 'jquery' );

    # figure out what shop/cart to use
    $rv->{shop} = DW::Shop->get;
    $rv->{cart} = $r->get_args->{newcart} ? DW::Shop::Cart->new_cart( $rv->{u} ) : $rv->{shop}->cart;

    # populate vars with cart display template
    $rv->{cart_display} = DW::Template->template_string( 'shop/cartdisplay.tt', $rv );
    return ( 1, $rv );
}

# handles the shop index page
sub shop_index_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    return DW::Template->render_template( 'shop/index.tt', $rv );
}

# handles the shop buy points page
sub shop_points_handler {
    my ( $ok, $rv ) = _shop_controller();
    return $rv unless $ok;

    my %errs;
    $rv->{errs} = \%errs;

    my $r = DW::Request->get;
    if ( LJ::did_post() ) {
        my $args = $r->post_args;

        # error check the user
        my $u = LJ::load_user( $args->{foruser} )
            or $errs{foruser} = 'Invalid account.';
        if ( $u ) {
            if ( $u->is_visible && $u->is_person ) {
                $rv->{foru} = $u;
            } else {
                $errs{foruser} = 'Account must be active and a personal account.';
            }
        }

        # error check the points
        my $points = $args->{points} + 0;
        $errs{points} = 'Points must be in range 30 to 5,000.'
            unless $points >= 30 && $points <= 5000;
        $rv->{points} = $points;

        # looks good, add it!
        unless ( keys %errs ) {
            $rv->{cart}->add_item(
                DW::Shop::Item::Points->new( target_userid => $u->id, from_userid => $rv->{remote}->id, points => $points )
            );
        
            return $r->redirect( "$LJ::SITEROOT/shop" );
        }
        
    } else {
        my $for = $r->get_args->{for};

        if ( ! $for || $for eq 'self' ) {
            $rv->{foru} = $rv->{remote};
        } elsif ( $for ) {
            my $fu = LJ::load_user( $for );
            $rv->{foru} = $fu if $fu;
        }
    }

    return DW::Template->render_template( 'shop/points.tt', $rv );
}


1;
