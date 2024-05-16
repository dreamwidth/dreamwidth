#!/usr/bin/perl
#
# DW::Controller::Shop::Points
#
# This controller handles the shop buy points page
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

package DW::Controller::Shop::Points;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;

DW::Routing->register_string( '/shop/points', \&shop_points_handler, app => 1 );

sub shop_points_handler {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my %errs;
    $rv->{errs} = \%errs;

    my $r = DW::Request->get;
    return $r->redirect($LJ::SHOPROOT) unless exists $LJ::SHOP{points};

    if ( $r->did_post ) {
        my $args = $r->post_args;
        die "invalid auth\n" unless LJ::check_form_auth( $args->{lj_form_auth} );

        my $u      = LJ::load_user( $args->{foruser} );
        my $points = int( $args->{points} + 0 );
        my $item;    # provisionally create the item to access object methods

        if ( !$u ) {
            $errs{foruser} = LJ::Lang::ml('shop.item.points.canbeadded.notauser');

        }
        elsif (
            $item = DW::Shop::Item::Points->new(
                target_userid => $u->id,
                from_userid   => $remote->id,
                points        => $points
            )
            )
        {
            # error check the user
            if ( $item->can_be_added_user( errref => \$errs{foruser} ) ) {
                $rv->{foru} = $u;
                delete $errs{foruser};    # undefined
            }

            # error check the points
            if ( $item->can_be_added_points( errref => \$errs{points} ) ) {
                $rv->{points} = $points;
                delete $errs{points};     # undefined
            }

        }
        else {
            $errs{foruser} = LJ::Lang::ml('shop.item.points.canbeadded.itemerror');
        }

        # looks good, add it!
        unless ( keys %errs ) {
            $rv->{cart}->add_item($item);
            return $r->redirect($LJ::SHOPROOT);
        }

    }
    else {
        my $for = $r->get_args->{for};

        if ( !$for || $for eq 'self' ) {
            $rv->{foru} = $remote;
        }
        else {
            $rv->{foru} = LJ::load_user($for);
        }
    }

    return DW::Template->render_template( 'shop/points.tt', $rv );
}

1;
