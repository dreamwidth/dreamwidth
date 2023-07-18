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
        my %item_data;
        $item_data{from_userid} = $remote ? $remote->id : 0;

        if ( $post->{for} eq 'self' ) {
            if ( $remote && $remote->is_personal ) {
                $item_data{target_userid} = $remote->id;
            }
            else {
                return error_ml('widget.shopitemoptions.error.notloggedin');
            }
        }
        elsif ( $post->{for} eq 'gift' ) {
            my $target_u   = LJ::load_user( $post->{username} );
            my $user_check = validate_target_user( $target_u, $remote );

            if ( defined $user_check->{error} ) {
                $errors->add( 'username', $user_check->{error} );
            }
            else {
                $item_data{target_userid} = $target_u->id;
            }

        }

        if ( $post->{deliverydate} ) {
            $post->{deliverydate} =~ /(\d{4})-(\d{2})-(\d{2})/;
            my $given_date = DateTime->new(
                year  => $1,
                month => $2,
                day   => $3,
            );

            my $time_check = DateTime->compare( $given_date, DateTime->today );

            if ( $time_check < 0 ) {

                # we were given a date in the past
                $errors->add( 'deliverydate', 'time cannot be in the past' );    #FIXME
            }
            elsif ( $time_check > 0 ) {

                # date is in the future, add it.
                $item_data{deliverydate} = $given_date->date;
            }

        }

        unless ( $errors->exist ) {
            $item_data{anonymous} = 1
                if $post->{anonymous} || !$remote;

            $item_data{reason} = LJ::strip_html( $post->{reason} );

            my ( $rv, $err ) =
                $rv->{cart}
                ->add_item( DW::Shop::Item::Rename->new( cannot_conflict => 1, %item_data ) );

            $errors->add( '', $err ) unless $rv;

            unless ( $errors->exist ) {
                return $r->redirect("$LJ::SITEROOT/shop");
            }
        }

    }

    $vars->{errors} = $errors;

    return DW::Template->render_template( 'shop/renames.tt', $vars );
}

sub validate_target_user {
    my ( $target_u, $remote ) = shift;
    return { error => 'widget.shopitemoptions.error.invalidusername' }
        unless LJ::isu($target_u);

    return { error => 'widget.shopitemoptions.error.expungedusername' }
        if $target_u->is_expunged;

    return { error => 'widget.shopitemoptions.error.banned' }
        if $remote && $target_u->has_banned($remote);

    return { success => 1 };
}

1;
