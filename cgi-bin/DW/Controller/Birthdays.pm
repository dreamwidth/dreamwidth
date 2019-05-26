#!/usr/bin/perl
#
# DW::Controller::Birthdays
#
# This controller is for the birthdays page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Birthdays;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/birthdays', \&birthdays_handler, app => 1 );

sub birthdays_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $u;
    my $remote    = LJ::get_remote();
    my $otheruser = 0;

    my $r              = DW::Request->get;
    my $requested_user = $r->get_args->{user};
    if ($requested_user) {
        $u = LJ::load_user($requested_user);

        # invalid username
        return error_ml(
            '/birthdays.tt.error.invaliduser1',
            {
                user => LJ::ehtml($requested_user),
            }
        ) unless $u;

        # selected user not visible
        return error_ml(
            '/birthdays.tt.error.badstatus',
            {
                user => $u->ljuser_display,
            }
        ) unless $u->is_visible;

        # flag to acknowledge we are working with another user
        $otheruser = 1;
    }
    else {
        # work with logged in user; $otheruser = 0
        $u = $remote;
    }

    my @bdays = $u->get_birthdays( full => 1 );
    my $vars;
    my $current_month = 0;

    foreach my $bday (@bdays) {
        my ( $mymon, $myday, $user ) = @$bday;
        my $current_user = LJ::load_user($user);
        my $month        = LJ::Lang::month_long_ml($mymon);
        my $day          = sprintf( '%02d', $myday );
        my $ljname       = $current_user->ljuser_display;
        my $name         = $current_user->name_html;
        if ( $mymon != $current_month ) {
            push @{ $vars->{bdaymonths} }, $month;
            $current_month = $mymon;
        }
        push @{ $vars->{bdays}->{$month} },
            {
            ljname => $ljname,
            name   => $name,
            day    => $day
            };
    }
    $vars->{otheruser} = $otheruser;
    $vars->{u}         = $u;

    $vars->{nobirthdays} = 1 unless @bdays;
    return DW::Template->render_template( 'birthdays.tt', $vars );

}

1;
