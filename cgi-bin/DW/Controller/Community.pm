#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Community;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;

=head1 NAME

DW::Controller::Community - Community management pages

=cut


DW::Routing->register_string( "/community/index", \&index_handler, app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $vars = {
        remote => $rv->{remote},
        remote_admins_communities => @{LJ::load_rel_target( $rv->{remote}, 'A' ) || []} ? 1 : 0,
        community_manage_links => LJ::Hooks::run_hook( 'community_manage_links' ) || "",

        # implemented as a hook because most/all the links are to
        # dreamwidth.org-specific FAQs. see cgi-bin/DW/Hooks/Community.pm
        # in dw-nonfree as an example to create your own.
        faq_links => LJ::Hooks::run_hook( 'community_faqs' ) || "",

        # hook is to list dw-community-promo;
        # define your own in a hook if you have a similar community or want to
        # add other links to the list.
        community_search_links => LJ::Hooks::run_hook( 'community_search_links' ) || "",

        recently_active_comms => DW::Widget::RecentlyActiveComms->render,
        newly_created_comms => DW::Widget::NewlyCreatedComms->render,
        official_comms => LJ::Hooks::run_hook( 'official_comms' ) || "",
    };

    return DW::Template->render_template( 'community/index.tt', $vars );
}


1;