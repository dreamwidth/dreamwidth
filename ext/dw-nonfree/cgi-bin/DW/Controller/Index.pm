#!/usr/bin/perl
#
# DW::Controller::Index
#
# Controller for the site homepage.
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Controller::Index;

use strict;
use warnings;

use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::Panel;
use DW::InviteCodes;

DW::Routing->register_string( "/index", \&index_handler, app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;
    my $remote = $rv->{remote};
    my $vars;

    if ($remote) {
        $vars->{remote} = $remote;
        $vars->{panel} = DW::Panel->init( u => $remote )
    } else {
        # possible strings are:
        # .create.join_dreamwidth.content                      - normal
        # .create.join_dreamwidth.content.noinvites            - will be in use occasionally
        # .create.join_dreamwidth.content.nopayments           - was in use before payments were set up
        # .create.join_dreamwidth.content.noinvites.nopayments - highly unlikely to ever be in use on DW.org, but possible on Dreamhacks
        my $string = ".create.join_dreamwidth.content";
        if ( ! $LJ::USE_ACCT_CODES )          { $string .= ".noinvites";  }
        if ( ! LJ::is_enabled( 'payments' ) ) { $string .= ".nopayments"; }

        # if you change the number of columns here, you'll need to tweak the width
        # percentage for .links-column in the CSS file accordingly.
        my @columns = (
            {
                name => 'about',
                items => [
                    [ '/about', 'about_dreamwidth' ],
#                    [ '#', 'site_tour' ],
                    [ '/legal/principles', 'guiding_principles' ],
                ],
            },
            {
                name => 'community',
                items => [
                    [ 'https://dw-news.dreamwidth.org/', 'site_news' ],
                    [ '/latest', 'latest_things', 'footnote' ],
                    [ '/random', 'random_journal', 'footnote' ],
                    [ '/community/random', 'random_community', 'footnote' ],
                ],
                footnote => 'no_screening',
            },
            {
                name => 'support',
                items => [
                    [ '/support/faq', 'faq' ],
                    [ '/support/', 'support' ],
                ],
            },
        );

        push @{$columns[1]->{items}}, [ 'https://dw-codesharing.dreamwidth.org/', 'codeshare' ]
            if $LJ::USE_ACCT_CODES;

        $vars->{invite_length} = DW::InviteCodes::CODE_LEN;
        $vars->{string} = $string;
        $vars->{columns} = \@columns;
        $vars->{use_acct_codes} = $LJ::USE_ACCT_CODES;
        $vars->{use_payments} = LJ::is_enabled( 'payments' );
    }


    return DW::Template->render_template( 'index.tt', $vars );
}

1;
