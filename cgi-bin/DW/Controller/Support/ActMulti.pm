#!/usr/bin/perl
#
# DW::Controller::Support::ActMulti
#
# Handles /support/actmulti, the POST-only endpoint behind the mass-action
# buttons on the support board (/support/help): close, close-with-points, and
# move a batch of support requests, then redirect back to the board.
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

package DW::Controller::Support::ActMulti;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Support;

DW::Routing->register_string( '/support/actmulti', \&actmulti_handler, app => 1, no_cache => 1 );

sub actmulti_handler {
    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $ml_scope = '/support/actmulti.tt';

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $post   = $r->post_args;

    my $spcatid = $post->{spcatid};
    my $cats    = LJ::Support::load_cats($spcatid);
    my $cat     = $cats->{$spcatid};
    return error_ml("$ml_scope.cat.not.exist") unless $cat;

    # ids of the checked requests
    my @ids = map { $_ + 0 } grep { $post->{"check_$_"} } split( ':', $post->{ids} );
    return error_ml("$ml_scope.no.request") unless @ids;

    # just to be sane, limit it to 1000 requests
    @ids = splice @ids, 0, 1000 if scalar @ids > 1000;

    if ( $post->{'action:close'} ) {
        my $can_close = 0;
        $can_close = 1 if $remote->has_priv( 'supportclose', $cat->{catkey} );
        $can_close = 1 if $cat->{public_read} && $remote->has_priv( 'supportclose', '' );
        return error_ml("$ml_scope.not.have.access") unless $can_close;

        # close all of these requests
        my $dbh = LJ::get_db_writer();
        my $in  = join ',', ('?') x @ids;
        $dbh->do(
            "UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(), "
                . "timemodified=UNIX_TIMESTAMP() WHERE spid IN ($in) AND spcatid = ?",
            undef, @ids, $spcatid
        );

        _log_requests( $dbh, $remote, \@ids, '(Request closed as part of mass closure.)' );

        return $r->redirect( sprintf( $post->{ret}, '' ) ) if $post->{ret};
        return success_ml("$ml_scope.request.specified");
    }
    elsif ( $post->{'action:closewithpoints'} ) {
        return error_ml("$ml_scope.not.have.access")
            unless LJ::Support::can_close_cat( { _cat => $cat }, $remote );

        # implement a limit so that we don't overload the DB and/or time out
        my @filtered_ids = splice( @ids, 0, 50 );

        my $requests = LJ::Support::load_requests( \@filtered_ids );
        LJ::Support::close_request_with_points( $_, $cat, $remote ) foreach @$requests;

        # @ids now holds the overflow beyond 50; pass it back so the board
        # re-marks those requests for the next round
        return $r->redirect( sprintf( $post->{ret}, '&mark=' . join( ',', @ids ) ) )
            if $post->{ret};
        return success_ml("$ml_scope.request.specified");
    }
    elsif ( $post->{'action:move'} ) {
        return error_ml("$ml_scope.not.have.access.move.request")
            unless LJ::Support::can_perform_actions( { _cat => $cat }, $remote );

        my $newcat  = $post->{changecat} + 0;
        my $allcats = LJ::Support::load_cats();
        return error_ml("$ml_scope.category.invalid") unless $allcats->{$newcat};

        # move all of these requests
        my $dbh = LJ::get_db_writer();
        my $in  = join ',', ('?') x @ids;
        $dbh->do( "UPDATE support SET spcatid = ? WHERE spid IN ($in) AND spcatid = ?",
            undef, $newcat, @ids, $spcatid );

        _log_requests( $dbh, $remote, \@ids,
                  "(Mass move from $allcats->{$spcatid}->{catname} "
                . "to $allcats->{$newcat}->{catname}.)" );

        return $r->redirect( sprintf( $post->{ret}, '' ) ) if $post->{ret};
        return success_ml("$ml_scope.request.moved");
    }

    # no recognized action button (not reachable from the real form): send
    # them back to the support board rather than render an empty page
    return $r->redirect("$LJ::SITEROOT/support/");
}

# Insert one internal supportlog row per request id, all sharing $message.
# Parameterized so category names (in the move notice) can't break out of the
# SQL string literal.
sub _log_requests {
    my ( $dbh, $remote, $ids, $message ) = @_;

    my @stmts = ("(?, UNIX_TIMESTAMP(), 'internal', ?, ?)") x @$ids;
    my @bind  = map { ( $_, $remote->{userid}, $message ) } @$ids;

    $dbh->do(
        "INSERT INTO supportlog (spid, timelogged, type, userid, message) VALUES "
            . join( ',', @stmts ),
        undef, @bind
    );
}

1;
