#!/usr/bin/perl
#
# DW::Controller::Shop::TransferPoints
#
# This controller handles when someone wants to transfer points.
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

package DW::Controller::Shop::TransferPoints;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;

DW::Routing->register_string( '/shop/transferpoints', \&shop_transfer_points_handler, app => 1 );

sub shop_transfer_points_handler {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my %errs;
    $rv->{errs}       = \%errs;
    $rv->{has_points} = $remote->shop_points;

    my $r = DW::Request->get;
    if ( $r->did_post ) {
        my $args = $r->post_args;
        die "invalid auth\n" unless LJ::check_form_auth( $args->{lj_form_auth} );

        my $u      = LJ::load_user( $args->{foruser} );
        my $points = int( $args->{points} + 0 );

        if ( !$u ) {
            $errs{foruser} = LJ::Lang::ml('shop.item.points.canbeadded.notauser');
            $rv->{can_have_reason} = DW::Shop::Item::Points->can_have_reason;

        }
        elsif (
            my $item = DW::Shop::Item::Points->new(
                target_userid => $u->id,
                from_userid   => $remote->id,
                points        => $points,
                transfer      => 1
            )
            )
        {
            # provisionally create the item to access object methods

            # error check the user
            if ( $item->can_be_added_user( errref => \$errs{foruser} ) ) {
                $rv->{foru} = $u;
                delete $errs{foruser};    # undefined
            }

            # error check the points
            if ( $item->can_be_added_points( errref => \$errs{points} ) ) {

                # remote must have enough points to transfer
                if ( $remote->shop_points < $points ) {
                    $errs{points} = LJ::Lang::ml('shop.item.points.canbeadded.insufficient');
                }
                else {
                    $rv->{points} = $points;
                    delete $errs{points};    # undefined
                }
            }

            # Note: DW::Shop::Item::Points->can_have_reason doesn't check args,
            # but someone will suggest it do so in the future, so let's save time.
            $rv->{can_have_reason} = $item->can_have_reason( user => $u, anon => $args->{anon} );

        }
        else {
            $errs{foruser} = LJ::Lang::ml('shop.item.points.canbeadded.itemerror');
            $rv->{can_have_reason} = DW::Shop::Item::Points->can_have_reason;
        }

        # copy down anon value and reason
        $rv->{anon}   = $args->{anon} ? 1 : 0;
        $rv->{reason} = LJ::strip_html( $args->{reason} );

        # if this is a confirmation page, then confirm if there are no errors
        if ( $args->{confirm} && !scalar keys %errs ) {

            # first add the points to the other person... wish we had transactions here!
            $u->give_shop_points(
                amount => $points,
                reason => sprintf( 'transfer from %s(%d)', $remote->user, $remote->id )
            );
            $remote->give_shop_points(
                amount => -$points,
                reason => sprintf( 'transfer to %s(%d)', $u->user, $u->id )
            );

            my $get_text = sub { LJ::Lang::get_default_text(@_) };

            # send notification to person transferring the points...
            {
                my $reason = $rv->{reason};
                my $vars   = {
                    from     => $remote->display_username,
                    points   => $points,
                    to       => $u->display_username,
                    reason   => $reason,
                    sitename => $LJ::SITENAMESHORT,
                    reason   => $reason,
                };
                my $body =
                      $reason
                    ? $get_text->( 'esn.sentpoints.body.reason',   $vars )
                    : $get_text->( 'esn.sentpoints.body.noreason', $vars );

                LJ::send_mail(
                    {
                        to       => $remote->email_raw,
                        from     => $LJ::ACCOUNTS_EMAIL,
                        fromname => $LJ::SITENAME,
                        subject  => $get_text->(
                            'esn.sentpoints.subject',
                            {
                                sitename => $LJ::SITENAMESHORT,
                                to       => $u->display_username,
                            }
                        ),
                        body => $body,
                    }
                );
            }

            # send notification to person receiving the points...
            {
                my $e = $rv->{anon} ? 'anon' : 'user';
                my $reason =
                    ( $rv->{reason} && $rv->{can_have_reason} )
                    ? $get_text->( "esn.receivedpoints.reason", { reason => $rv->{reason} } )
                    : '';
                my $body = $get_text->(
                    "esn.receivedpoints.$e.body",
                    {
                        user     => $u->display_username,
                        points   => $points,
                        from     => $remote->display_username,
                        sitename => $LJ::SITENAMESHORT,
                        store    => "$LJ::SITEROOT/shop/",
                        reason   => $reason,
                    }
                );

                # FIXME: esnify the notification
                LJ::send_mail(
                    {
                        to       => $u->email_raw,
                        from     => $LJ::ACCOUNTS_EMAIL,
                        fromname => $LJ::SITENAME,
                        subject  => $get_text->(
                            'esn.receivedpoints.subject', { sitename => $LJ::SITENAMESHORT }
                        ),
                        body => $body,
                    }
                );
            }

            # happy times ...
            $rv->{transferred} = 1;

            # else, if still no errors, send to the confirm pagea
        }
        elsif ( !scalar keys %errs ) {
            $rv->{confirm} = 1;
        }

    }
    else {
        if ( my $for = $r->get_args->{for} ) {
            $rv->{foru} = LJ::load_user($for);
        }

        if ( my $points = $r->get_args->{points} ) {
            $rv->{points} = $points + 0
                if $points > 0 && $points <= 5000;
        }

        $rv->{can_have_reason} = DW::Shop::Item::Points->can_have_reason;
    }

    return DW::Template->render_template( 'shop/transferpoints.tt', $rv );
}

1;
