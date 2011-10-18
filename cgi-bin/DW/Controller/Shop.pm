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
DW::Routing->register_string( '/shop/transferpoints', \&shop_transfer_points_handler, app => 1 );

# our basic shop controller, this does setup that is unique to all shop
# pages and everybody should call this first.  returns the same tuple as
# the controller method.
sub _shop_controller {
    my %args = ( @_ );
    my $r = DW::Request->get;

    # if payments are disabled, do nothing
    unless ( LJ::is_enabled( 'payments' ) ) {
        $r->redirect( "$LJ::SITEROOT/" );
        return ( 0, LJ::Lang::ml( 'shop.unavailable' ) );
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

    # call any hooks to do things before we return success
    LJ::Hooks::run_hooks( 'shop_controller', $rv );

    return ( 1, $rv );
}

# handles the shop index page
sub shop_index_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    return DW::Template->render_template( 'shop/index.tt', $rv );
}

# if someone wants to transfer points...
sub shop_transfer_points_handler {
    my ( $ok, $rv ) = _shop_controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my %errs;
    $rv->{errs} = \%errs;
    $rv->{has_points} = $remote->shop_points;

    my $r = DW::Request->get;
    if ( $r->did_post ) {
        my $args = $r->post_args;
        die "invalid auth\n" unless LJ::check_form_auth( $args->{lj_form_auth} );

        my $u = LJ::load_user( $args->{foruser} );
        my $points = int( $args->{points} + 0 );

        if ( !$u ) {
            $errs{foruser} = LJ::Lang::ml( 'shop.item.points.canbeadded.notauser' );

        } elsif ( my $item = DW::Shop::Item::Points->new( target_userid => $u->id, from_userid => $remote->id, points => $points, transfer => 1 ) ) {
            # provisionally create the item to access object methods

            # error check the user
            if ( $item->can_be_added_user( errref => \$errs{foruser} ) ) {
                $rv->{foru} = $u;
                delete $errs{foruser};  # undefined
            }

            # error check the points
            if ( $item->can_be_added_points( errref => \$errs{points} ) ) {
                # remote must have enough points to transfer
                if ( $remote->shop_points < $points ) {
                    $errs{points} = LJ::Lang::ml( 'shop.item.points.canbeadded.insufficient' );
                } else {
                    $rv->{points} = $points;
                    delete $errs{points};  # undefined
                }
            }

            # Note: DW::Shop::Item::Points->can_have_reason doesn't check args,
            # but someone will suggest it do so in the future, so let's save time.
            $rv->{can_have_reason} = $item->can_have_reason( user => $u, anon => $args->{anon} );

        } else {
            $errs{foruser} = LJ::Lang::ml( 'shop.item.points.canbeadded.itemerror' );
        }

        # copy down anon value and reason
        $rv->{anon} = $args->{anon} ? 1 : 0;
        $rv->{reason} = LJ::strip_html( $args->{reason} );

        # if this is a confirmation page, then confirm if there are no errors
        if ( $args->{confirm} && ! scalar keys %errs ) {
            # first add the points to the other person... wish we had transactions here!
            $u->give_shop_points( amount => $points, reason => sprintf( 'transfer from %s(%d)', $remote->user, $remote->id ) );
            $remote->give_shop_points( amount => -$points, reason => sprintf( 'transfer to %s(%d)', $u->user, $u->id ) );

            my $get_text = sub { LJ::Lang::get_text( $u->prop( 'browselang' ), $_[0], undef, $_[1] ) };

            # send notification ...
            my $e = $rv->{anon} ? 'anon' : 'user';
            my $reason = ( $rv->{reason} && $rv->{can_have_reason} ) ? $get_text->( "esn.receivedpoints.reason", { reason => $rv->{reason} } ) : '';
            my $body = $get_text->( "esn.receivedpoints.$e.body", {
                    user => $u->display_username,
                    points => $points,
                    from => $remote->display_username,
                    sitename => $LJ::SITENAMESHORT,
                    store => "$LJ::SITEROOT/shop/",
                    reason => $reason,
                } );

            # FIXME: esnify the notification
            LJ::send_mail( {
                to => $u->email_raw,
                from => $LJ::ACCOUNTS_EMAIL,
                fromname => $LJ::SITENAME,
                subject => $get_text->( 'esn.receivedpoints.subject', { sitename => $LJ::SITENAMESHORT } ),
                body => $body,
            } );

            # happy times ...
            $rv->{transferred} = 1;

        # else, if still no errors, send to the confirm pagea
        } elsif ( ! scalar keys %errs ) {
            $rv->{confirm} = 1;
        }

    } else {
        if ( my $for = $r->get_args->{for} ) {
            $rv->{foru} = LJ::load_user( $for );
        }

        if ( my $points = $r->get_args->{points} ) {
            $rv->{points} = $points+0
                if $points > 0 && $points <= 5000;
        }

        $rv->{can_have_reason} = DW::Shop::Item::Points->can_have_reason;
    }

    return DW::Template->render_template( 'shop/transferpoints.tt', $rv );
}

# handles the shop buy points page
sub shop_points_handler {
    my ( $ok, $rv ) = _shop_controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my %errs;
    $rv->{errs} = \%errs;

    my $r = DW::Request->get;
    if ( $r->did_post ) {
        my $args = $r->post_args;
        die "invalid auth\n" unless LJ::check_form_auth( $args->{lj_form_auth} );

        my $u = LJ::load_user( $args->{foruser} );
        my $points = int( $args->{points} + 0 );
        my $item;  # provisionally create the item to access object methods

        if ( !$u ) {
            $errs{foruser} = LJ::Lang::ml( 'shop.item.points.canbeadded.notauser' );

        } elsif ( $item = DW::Shop::Item::Points->new( target_userid => $u->id, from_userid => $remote->id, points => $points ) ) {
            # error check the user
            if ( $item->can_be_added_user( errref => \$errs{foruser} ) ) {
                $rv->{foru} = $u;
                delete $errs{foruser};  # undefined
            }

            # error check the points
            if ( $item->can_be_added_points( errref => \$errs{points} ) ) {
                $rv->{points} = $points;
                delete $errs{points};  # undefined
            }

        } else {
            $errs{foruser} = LJ::Lang::ml( 'shop.item.points.canbeadded.itemerror' );
        }

        # looks good, add it!
        unless ( keys %errs ) {
            $rv->{cart}->add_item( $item );
            return $r->redirect( "$LJ::SITEROOT/shop" );
        }

    } else {
        my $for = $r->get_args->{for};

        if ( ! $for || $for eq 'self' ) {
            $rv->{foru} = $remote;
        } else {
            $rv->{foru} = LJ::load_user( $for );
        }
    }

    return DW::Template->render_template( 'shop/points.tt', $rv );
}


1;
