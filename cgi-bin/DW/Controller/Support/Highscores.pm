#!/usr/bin/perl
#
# DW::Controller::Support::Highscores
#
# This controller is for the Support High Scores page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Highscores;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/highscores', \&highscores_handler, app => 1 );

sub highscores_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $user;
    my $user_url;

    my $vars = {};

    my $dbr = LJ::get_db_reader();
    my $sth;
    my %rank;

    $r = DW::Request->get;
    my $args = $r->get_args;

    $sth = $dbr->prepare( "SELECT statcat, statkey, statval FROM stats "
            . "WHERE statcat IN ('supportrank', 'supportrank_prev')" );

    $sth->execute;

    my $warn_nodata = 0;

    while ( my ( $cat, $userid, $rank ) = $sth->fetchrow_array ) {
        if ( $cat eq "supportrank" ) {
            $rank{$userid}->{'now'} = $rank;
        }
        else {
            $rank{$userid}->{'last'} = $rank;
        }
    }
    if ( !%rank ) {
        $warn_nodata = 1;
    }
    else {
        $sth = $dbr->prepare(
                  "SELECT u.userid, u.user, u.name, sp.totpoints AS 'points', sp.lastupdate "
                . "FROM user u, supportpointsum sp WHERE u.userid=sp.userid" );
        $sth->execute;
        my @rows;
        push @rows, $_ while $_ = $sth->fetchrow_hashref;
        if ( defined $args->{sort} && $args->{sort} eq "lastupdate" ) {
            @rows = sort { $b->{lastupdate} <=> $a->{lastupdate} } @rows;
        }
        else {
            @rows = sort { $b->{points} <=> $a->{points} } @rows;
        }

        # pagination:
        #   calculate the number of pages
        #   take the results and choose only a slice for display
        my $page      = int( $args->{page} || 0 ) || 1;
        my $page_size = 100;
        my $first     = ( $page - 1 ) * $page_size;
        my $total     = scalar(@rows);

        my $total_pages = POSIX::ceil( $total / $page_size );

        my $shown = $page_size * $page - 1;
        if ( $shown >= $total ) {
            $shown = $total - 1;
        }
        my $rank       = 0;
        my $lastpoints = 0;
        my $buildup    = 0;
        unless ( $first == 0 ) {
            foreach my $row ( @rows[ 0 .. $first ] ) {
                if ( $row->{'points'} != $lastpoints ) {
                    $lastpoints = $row->{'points'};
                    $rank += ( 1 + $buildup );
                    $buildup = 0;
                }
                else {
                    $buildup++;
                }
            }
        }

        $vars->{pages} = {
            current     => $page,
            total_pages => $total_pages,
        };

        my $count = 0;
        foreach my $row ( @rows[ $first .. $shown ] ) {
            my $userid = $row->{'userid'};
            my $user   = LJ::load_user( $row->{'user'} );
            next if $user->is_expunged;
            $count++;
            my $ljname = $user->ljuser_display;
            my $name   = $user->name_html;
            if ( $row->{'points'} != $lastpoints ) {
                $lastpoints = $row->{'points'};
                $rank += ( 1 + $buildup );
                $buildup = 0;
            }
            else {
                $buildup++;
            }
            my $change = 0;
            if ( $rank{$userid}->{'now'} && $rank{$userid}->{'last'} ) {
                $change = $rank{$userid}->{'last'} -
                    $rank{$userid}->{'now'};    # from 5th to 4th is 5-4 = 1 (+1 for increase)
            }
            my $points = $row->{'points'};
            my $s      = $points > 1 ? "s" : "";

            push @{ $vars->{scores} },
                {
                ljname => $ljname,
                name   => $name,
                points => $points,
                change => $change,
                s      => $s,
                rank   => $rank,
                };
        }
        $vars->{total} = $total;
        $vars->{count} = $count;
    }

    $vars->{warn_nodata} = $warn_nodata;

    return DW::Template->render_template( 'support/highscores.tt', $vars );

}

1;
