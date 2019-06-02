#!/usr/bin/perl
#
# DW::Controller::MassPrivacy
#
# This controller is for /editprivacy.
#
# Authors:
#      R Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::MassPrivacy;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use LJ::MassPrivacy;

DW::Routing->register_string( '/editprivacy', \&editprivacy_handler, app => 1 );

sub editprivacy_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;
    my $u      = $rv->{u};
    my $remote = $rv->{remote};

    my ( $s_dt, $e_dt, $posts );

    return "This feature is currently disabled."
        unless LJ::is_enabled('mass_privacy');

    return error_ml('editprivacy.tt.unable') unless $u->can_use_mass_privacy;

    my $mode = $POST->{'mode'} || $GET->{'mode'} || "init";
    my $more_public = 0;    # flag indiciating if security is becoming more public

    # Check fields
    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        return error_ml('error.invalidform')
            unless LJ::check_form_auth( $POST->{lj_form_auth} );

        # Timeframe
        $errors->add( "time", ".error.time" ) unless $POST->{'time'};

        # date range
        if ( $POST->{'time'} eq 'range' && $mode eq 'change' ) {
            if (   !( $POST->{'s_year'} =~ /\d+/ )
                || !( $POST->{'s_mon'} =~ /\d+/ )
                || !( $POST->{'s_day'} =~ /\d+/ ) )
            {
                $errors->add( "time", ".error.time.start" );
            }
            if (   !( $POST->{'e_year'} =~ /\d+/ )
                || !( $POST->{'e_mon'} =~ /\d+/ )
                || !( $POST->{'e_day'} =~ /\d+/ ) )
            {
                $errors->add( "time", ".error.time.end" );
            }

            # Round down the day of month to the last day of the month
            if ( $POST->{'s_day'} > LJ::days_in_month( $POST->{'s_mon'}, $POST->{'s_year'} ) ) {
                $POST->{'s_day'} =
                    LJ::days_in_month( $POST->{'s_mon'}, $POST->{'s_year'} );
            }
            if ( $POST->{'e_day'} > LJ::days_in_month( $POST->{'e_mon'}, $POST->{'e_year'} ) ) {
                $POST->{'e_day'} =
                    LJ::days_in_month( $POST->{'e_mon'}, $POST->{'e_year'} );
            }
        }

        # security must change
        if ( $POST->{'s_security'} eq $POST->{'e_security'} ) {
            $errors->add( undef, ".error.security" );
        }

        # display initial page if errors
        $mode = 'init' if $errors->exist;

        # check if security is becoming more public
        $more_public = 1 if $POST->{'s_security'} eq 'private';
        $more_public = 1
            if $POST->{'s_security'} eq 'friends'
            && $POST->{'e_security'} eq 'public';

        if (   ( $mode eq 'amsure' )
            && $more_public
            && !LJ::auth_okay( $u, $POST->{password}, undef, undef, undef ) )
        {
            $errors->add( undef, ".error.password" );
            $mode = 'change' if $errors->exist;
        }
    }

    # map security form values to 0) DB value 1) From string 2) To string
    my %security = (
        'public'  => [ 'public',  BML::ml('label.security.public2') ],
        'friends' => [ 'usemask', BML::ml('label.security.accesslist') ],
        'private' => [ 'private', BML::ml('label.security.private2') ]
    );

    my @security = (
        'public',  BML::ml('label.security.public2'),
        'friends', BML::ml('label.security.accesslist'),
        'private', BML::ml('label.security.private2')
    );

    # Initial view of page
    if ( $mode eq "change" ) {

        my ( $s_unixtime, $e_unixtime );

        if ( $POST->{'time'} eq 'range' ) {

            # if this step reloads, due to missing password
            if ( $POST->{s_unixtime} && $POST->{e_unixtime} ) {
                $s_unixtime = $POST->{s_unixtime};
                $e_unixtime = $POST->{e_unixtime};
            }
            else {
                # Convert dates to unixtime
                use DateTime;
                $s_dt = DateTime->new(
                    year  => $POST->{'s_year'},
                    month => $POST->{'s_mon'},
                    day   => $POST->{'s_day'}
                );
                $e_dt = DateTime->new(
                    year  => $POST->{'e_year'},
                    month => $POST->{'e_mon'},
                    day   => $POST->{'e_day'}
                );
                $s_unixtime = $s_dt->epoch;
                $e_unixtime = $e_dt->epoch;

            }
            $posts = $u->get_post_count(
                'security'   => $security{ $POST->{'s_security'} }[0],
                'allowmask'  => ( $POST->{'s_security'} eq 'friends' ? 1 : 0 ),
                'start_date' => $s_unixtime,
                'end_date'   => $e_unixtime + 24 * 60 * 60
            );
        }
        else {
            $posts = $u->get_post_count(
                'security'  => $security{ $POST->{'s_security'} }[0],
                'allowmask' => ( $POST->{'s_security'} eq 'friends' ? 1 : 0 )
            );
        }

        # User is sure they want to update posts
    }
    elsif ( $mode eq 'amsure' ) {
        my $handle = LJ::MassPrivacy->enqueue_job(
            'userid'     => $u->{userid},
            's_security' => $security{ $POST->{s_security} }[0],
            'e_security' => $security{ $POST->{e_security} }[0],
            's_unixtime' => $POST->{s_unixtime},
            'e_unixtime' => $POST->{e_unixtime}
        );

        if ($handle) {
            $u->log_event(
                'mass_privacy_change',
                {
                    remote     => $remote,
                    s_security => $security{ $POST->{s_security} }[0],
                    e_security => $security{ $POST->{e_security} }[0],
                    s_unixtime => $POST->{s_unixtime},
                    e_unixtime => $POST->{e_unixtime}
                }
            );
            $r->header_out( Location => "$LJ::SITEROOT/editprivacy?mode=secured" );
            return $r->REDIRECT;
        }

    }

    my @days   = map { $_, $_ } ( 1 .. 31 );
    my @months = map { $_, LJ::Lang::month_long_ml($_) } ( 1 .. 12 );
    my $vars   = {
        mode          => $mode,
        POST          => $POST,
        more_public   => $more_public,
        day_list      => \@days,
        month_list    => \@months,
        security_list => \@security,
        security      => \%security,
        errors        => $errors,
        s_dt          => $s_dt,
        e_dt          => $e_dt,
        posts         => $posts,
        u             => $u,
    };

    return DW::Template->render_template( 'editprivacy.tt', $vars );
}
1;
