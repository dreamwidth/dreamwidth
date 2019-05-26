#!/usr/bin/perl
#
# DW::Controller::Journal::Protected
#
# Displays when a user tries to access protected content.
#
# Author:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Journal::Protected;

use strict;

use DW::Controller;
use DW::Template;
use DW::Routing;
use DW::Request;

DW::Routing->register_string( "/journal/adult_concepts", \&adult_concepts_handler, app => 1 );
DW::Routing->register_string( "/journal/adult_explicit", \&adult_explicit_handler, app => 1 );
DW::Routing->register_string(
    "/journal/adult_explicit_blocked",
    \&adult_explicit_blocked_handler,
    app => 1
);

sub _init_vars {
    my ( $type, $journal, $entry ) = @_;
    return {
        type     => $type,
        form_url => LJ::create_url(
            DW::Logic::AdultContent->adult_interstitial_path( type => $type ),
            host => $LJ::DOMAIN_WEB
        ),

        entry   => $entry,
        journal => $journal,

        poster => defined $entry ? $entry->poster : $journal,
        markedby => defined $entry ? $entry->adult_content_marker : $journal->adult_content_marker,
        reason => DW::Logic::AdultContent->interstitial_reason( $journal, $entry ),
    };
}

sub _extract_from_request {
    my $r    = $_[0];
    my $get  = $r->get_args;
    my $post = $r->post_args;

    return ( $r->note('returl') || $post->{ret} || $get->{ret},
        $r->pnote('entry'), $r->pnote('user'), );
}

sub adult_concepts_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    my ( $returl, $entry, $journal ) = _extract_from_request($r);
    my $type = "concepts";

    # reload this entry if the user is logged in and is not choosing to
    # hide adult content since otherwise, the user shouldn't be here
    return $r->redirect($returl) if $remote && $remote->hide_adult_content ne 'concepts';

    # if we posted, then record we did so and let them view the entry
    if ( $r->did_post && $returl ) {
        my $post = $r->post_args;
        DW::Logic::AdultContent->set_confirmed_pages(
            user          => $remote,
            journalid     => $post->{journalid},
            entryid       => $post->{entryid},
            adult_content => $type
        );
        return $r->redirect($returl);
    }

    # if we didn't provide a journal, then redirect away. We can't do anything here
    return $r->redirect($LJ::SITEROOT) unless $journal;

    my $vars = _init_vars( $type, $journal, $entry );
    $vars->{returl} = $returl;

    return DW::Template->render_template( 'journal/adult_content.tt', $vars );
}

sub adult_explicit_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    my ( $returl, $entry, $journal ) = _extract_from_request($r);
    my $type = "explicit";

    # reload this entry if the user is logged in, has an age, and is not
    # choosing to hide adult content since otherwise, the user shouldn't be here
    return $r->redirect($returl)
        if $remote && $remote->best_guess_age && $remote->hide_adult_content eq 'none';

    # if we posted, then record we did so and let them view the entry
    if ( $r->did_post && $returl ) {
        my $post = $r->post_args;
        DW::Logic::AdultContent->set_confirmed_pages(
            user          => $remote,
            journalid     => $post->{journalid},
            entryid       => $post->{entryid},
            adult_content => $type
        );
        return $r->redirect($returl);
    }

    # if we didn't provide a journal, then redirect away. We can't do anything here
    return $r->redirect($LJ::SITEROOT) unless $journal;

    my $vars = _init_vars( $type, $journal, $entry );
    $vars->{returl} = $returl;

    return DW::Template->render_template( 'journal/adult_content.tt', $vars );
}

sub adult_explicit_blocked_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    my ( $returl, $entry, $journal ) = _extract_from_request($r);
    my $type = "explicit_blocked";

    # if we didn't provide a journal, then redirect away. We can't do anything here
    return $r->redirect($LJ::SITEROOT) unless $journal;

    my $vars = _init_vars( $type, $journal, $entry );
    $vars->{returl} = $returl;
    delete $vars->{form_url};

    return DW::Template->render_template( 'journal/adult_content.tt', $vars );
}

1;
