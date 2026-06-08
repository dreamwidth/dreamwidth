#!/usr/bin/perl
#
# DW::Controller::Support::Act
#
# Acts on a support request (touch/reopen, close, lock, unlock) from a signed
# link of the form /support/act?action;spid;authcode[;splid]. Used by the
# support tooling and by the close links in support notification emails.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Support::Act;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/act', \&act_handler, app => 1 );

sub act_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $scope  = '/support/act.tt';
    my $remote = $rv->{remote};

    # The command rides in the raw query string: action;spid;authcode[;splid].
    my ( $action, $spid, $authcode, $splid );
    if ( $r->query_string =~ /^(\w+);(\d+);(\w{15})(?:;(\d+))?$/ ) {
        ( $action, $spid, $authcode, $splid ) = ( $1, $2, $3, $4 );
    }

    my $valid_action = $action && $action =~ /^(?:touch|close|unlock|lock)$/;

    # Title stays "Request #N" for any recognized action (even if it errors);
    # only an unrecognized/garbled command shows "Error".
    $rv->{page_title} = $valid_action ? "Request #$spid" : "Error";

    return error_ml("$scope.improper.arguments") unless $valid_action;

    LJ::Support::init_remote($remote);
    my $sp = LJ::Support::load_request($spid);

    return error_ml("$scope.invalid.authcode")
        unless $sp && $sp->{authcode} eq $authcode;

    my $auth = LJ::Support::mini_auth($sp);

    if ( $action eq 'touch' ) {
        return error_ml("$scope.request.locked") if LJ::Support::is_locked($sp);

        LJ::Support::touch_request($spid)
            or return error_ml("$scope.touch.failed");

        # Someone who can close goes straight back to the request; everyone else
        # (e.g. the requester reopening from an email link) gets a comment form.
        return $r->redirect("$LJ::SITEROOT/support/see_request?id=$spid")
            if LJ::Support::can_close( $sp, $remote );

        $rv->{state}   = 'touched';
        $rv->{spid}    = $spid;
        $rv->{auth}    = $auth;
        $rv->{is_open} = $sp->{state} eq 'open' ? 1 : 0;
        return DW::Template->render_template( 'support/act.tt', $rv );
    }

    if ( $action eq 'lock' ) {
        return error_ml("$scope.not.allowed.request")
            unless $remote && LJ::Support::can_lock( $sp, $remote );
        return error_ml("$scope.request.already.locked")
            if LJ::Support::is_locked($sp);

        LJ::Support::lock($sp);
        LJ::Support::append_request( $sp,
            { body => '(Locking request.)', remote => $remote, type => 'internal' } );

        $rv->{state} = 'locked';
        $rv->{spid}  = $sp->{spid};
        return DW::Template->render_template( 'support/act.tt', $rv );
    }

    if ( $action eq 'unlock' ) {
        return error_ml("$scope.request.already.unlock")
            unless $remote && LJ::Support::can_lock( $sp, $remote );
        return error_ml("$scope.request.not.locked")
            unless LJ::Support::is_locked($sp);

        LJ::Support::unlock($sp);
        LJ::Support::append_request( $sp,
            { body => '(Unlocking request.)', remote => $remote, type => 'internal' } );

        $rv->{state} = 'unlocked';
        $rv->{spid}  = $sp->{spid};
        return DW::Template->render_template( 'support/act.tt', $rv );
    }

    if ( $action eq 'close' ) {
        return error_ml("$scope.request.cannot.close")
            unless LJ::Support::can_close( $sp, $remote, $auth );

        if ( $sp->{state} eq 'open' ) {
            my $dbh = LJ::get_db_writer();

            # If a specific answer was credited (splid), award its author points
            # for a timely answer -- but never credit the requester themselves.
            $splid += 0;
            if ($splid) {
                my ( $userid, $timelogged, $aspid, $type ) = $dbh->selectrow_array(
                    "SELECT userid, timelogged, spid, type FROM supportlog WHERE splid=?",
                    undef, $splid );

                return error_ml("$scope.answer.you.credited") if $aspid != $spid;

                if ( $userid != $sp->{requserid} && $type eq 'answer' ) {
                    my $secold = $timelogged - $sp->{timecreate};
                    my $points = LJ::Support::calc_points( $sp, $secold );
                    LJ::Support::set_points( $spid, $userid, $points );
                }
            }

            $dbh->do(
                "UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(),"
                    . " timemodified=UNIX_TIMESTAMP() WHERE spid=?",
                undef, $spid
            );
        }

        # If the closer can sweep the category, jump to the next open request in
        # it; otherwise show the "closed" page with navigation links.
        if ( LJ::Support::can_close_cat( $sp, $remote ) ) {
            my $dbr    = LJ::get_db_reader();
            my $catid  = $sp->{_cat}->{spcatid};
            my ($next) = $dbr->selectrow_array(
                "SELECT MIN(spid) FROM support WHERE spcatid=? AND state='open'"
                    . " AND timelasthelp>timetouched AND spid>?",
                undef, $catid, $spid
            );

            return $r->redirect("$LJ::SITEROOT/support/see_request?id=$next") if $next;

            $rv->{state}  = 'closed_nav';
            $rv->{spid}   = $sp->{spid};
            $rv->{catkey} = $sp->{_cat}->{catkey};
            return DW::Template->render_template( 'support/act.tt', $rv );
        }

        $rv->{state} = 'closed_simple';
        return DW::Template->render_template( 'support/act.tt', $rv );
    }

    # Unreachable: $valid_action guards the action set above.
    return $r->redirect("$LJ::SITEROOT/support/");
}

1;
