#!/usr/bin/perl
#
# DW::Controller::Shop::Gifts
#
# This controller is for the random gift and circle gift shop pages.
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

package DW::Controller::Shop::Gifts;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;

DW::Routing->register_string( '/shop/randomgift', \&shop_randomgift_handler, app => 1 );
DW::Routing->register_string( '/shop/gifts',      \&shop_gifts_handler,      app => 1 );

# Gives a person a random active free user that they can choose to purchase a
# paid account for.
sub shop_randomgift_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $POST   = $r->post_args;

    my $type = $GET->{type};
    $type = 'P' unless $type && $type eq 'C';
    my $othertype = $type eq 'P' ? 'C' : 'P';

    if ( $r->did_post() ) {
        my $username = $POST->{username};
        my $u        = LJ::load_user($username);
        if ( LJ::isu($u) ) {
            return $r->redirect("$LJ::SHOPROOT/account?for=random&user=$username");
        }
    }

    my $randomu = DW::Pay::get_random_active_free_user($type);

    my $vars = {
        type       => $type,
        othertype  => $othertype,
        randomu    => $randomu,
        mysql_time => \&LJ::mysql_time
    };
    return DW::Template->render_template( 'shop/randomgift.tt', $vars );
}

# Provides a list of users in your Circle who might want a paid account.
sub shop_gifts_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    my ( @free, @expired, @expiring, @paid, @seed );

    my $circle = LJ::load_userids( $remote->circle_userids );

    foreach my $target ( values %$circle ) {

        if ( ( $target->is_person || $target->is_community ) && $target->is_visible ) {
            my $paidstatus = DW::Pay::get_paid_status($target);

            # account was never paid if it has no paidstatus row:
            push @free, $target unless defined $paidstatus;

            if ( defined $paidstatus ) {
                if ( $paidstatus->{permanent} ) {
                    push @seed, $target unless $target->is_official;
                }
                else {
                    # account is expired if the expiration date has passed:
                    push @expired, $target unless $paidstatus->{expiresin} > 0;

                    # account is expiring soon if the expiration time is
                    # within the next month:
                    push @expiring, $target
                        if $paidstatus->{expiresin} < 2592000
                        && $paidstatus->{expiresin} > 0;

                    # account is expiring in more than one month:
                    push @paid, $target if $paidstatus->{expiresin} >= 2592000;
                }
            }
        }
    }

    # now that we have the lists, sort them alphabetically by display name:
    my $display_sort = sub { $a->display_name cmp $b->display_name };
    @free     = sort $display_sort @free;
    @expired  = sort $display_sort @expired;
    @expiring = sort $display_sort @expiring;
    @paid     = sort $display_sort @paid;
    @seed     = sort $display_sort @seed;

    # build a list of free users in the circle, formatted with
    # the display username and a buy-a-gift link:
    # sort into two lists depending on whether it's a personal or community account
    my ( @freeusers, @freecommunities );
    foreach my $person (@free) {
        if ( $person->is_personal ) {
            push( @freeusers, $person );
        }
        else {
            push( @freecommunities, $person );
        }
    }

    my $vars = {
        remote          => $remote,
        freeusers       => \@freeusers,
        freecommunities => \@freecommunities,
        expusers        => \@expiring,
        lapsedusers     => \@expired,
        paidusers       => \@paid,
        seedusers       => \@seed,
    };

    return DW::Template->render_template( 'shop/gifts.tt', $vars );
}

1;
