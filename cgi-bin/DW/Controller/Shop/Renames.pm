#!/usr/bin/perl
#
# DW::Controller::Shop::Renames
#
# This is the page where a person can choose to buy a rename token for themselves or for another user.
#
# Authors:
#      Cocoa <cocoa@tokyo-tower.org>
#
# Copyright (c) 2010-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop::Renames;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;
use DW::FormErrors;

DW::Routing->register_string( '/shop/renames', \&shop_renames_handler, app => 1 );

sub shop_renames_handler {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = DW::Request->get;
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $post   = $r->post_args;

    return $r->redirect("$LJ::SITEROOT/shop")
        unless exists $LJ::SHOP{rename};

    # let's see what they're trying to do
    my $for = $GET->{for};
    return $r->redirect("$LJ::SITEROOT/shop")
        unless $for && $for =~ /^(?:self|gift)$/;

    # ensure they have a user if it's for self
    return error_ml('/shop/renames.tt.error.invalidself')
        if $for eq 'self' && ( !$remote || !$remote->is_personal );

    my $vars = {
        'for'        => $for,
        remote       => $remote,
        cart_display => $rv->{cart_display},
        date         => DateTime->today,
        formdata     => $post || { username => $GET->{user}, anonymous => ( $remote ? 0 : 1 ) }
    };

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        my $item_data = {};
        $item_data->{from_userid} = $remote ? $remote->id : 0;

        if ( $post->{for} eq 'self' ) {
            DW::Pay::for_self( $remote, $item_data );
        }
        elsif ( $post->{for} eq 'gift' ) {
            DW::Pay::for_gift( $remote, $post->{username}, $errors, $item_data );
        }

        if ( $post->{deliverydate} ) {
            DW::Pay::validate_deliverydate( $post->{deliverydate}, $errors, $item_data );
        }

        unless ( $errors->exist ) {
            $item_data->{anonymous} = 1
                if $post->{anonymous} || !$remote;

            $item_data->{reason} = LJ::strip_html( $post->{reason} );

            my ( $rv, $err ) =
                $rv->{cart}
                ->add_item( DW::Shop::Item::Rename->new( cannot_conflict => 1, %$item_data ) );

            $errors->add( '', $err ) unless $rv;

            unless ( $errors->exist ) {
                return $r->redirect("$LJ::SITEROOT/shop");
            }
        }

    }

    $vars->{errors} = $errors;

    return DW::Template->render_template( 'shop/renames.tt', $vars );
}

1;
