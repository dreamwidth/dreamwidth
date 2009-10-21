#
# Menu navigation logic
#
# Authors:
#     Janine Smith <janine@netrophic.com>
#     Sophie Hamilton <dw-bugzilla@theblob.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::MenuNav;

use strict;

# name: get_menu_navigation
#
# des: Returns the menu navigation structure for the site.
#
# args: (optional) An LJ::User object for which the 'display' fields should be
#       calculated. Defaults to the remote user.
#
# returns: an arrayref of top-level menu items, each represented as a hashref
#          describing the menu as follows:
#              - name:  the short (URL-friendly) name for this menu.
#              - items:  an arrayref of menu items, containing hashrefs
#                        giving the details for each one as follows:
#                            - url:  the URL that the link should lead to
#                            - text:  the ML name of the string to use for the
#                                     anchor
#                            - display:  if true, this menu item is applicable
#                                        to the given LJ::User object (or
#                                        remote if not given), and should be
#                                        shown.
sub get_menu_navigation {
    my ( $class, $u ) = @_;

    $u ||= LJ::get_remote();

    my ( $userpic_count, $userpic_max, $inbox_count );
    if ( $u ) {
        $userpic_count = $u->get_userpic_count;
        $userpic_max = $u->userpic_quota;

        my $inbox = $u->notification_inbox;
        $inbox_count = $inbox->unread_count;
    }

    # constants for display key
    my $loggedin = ( defined( $u ) && $u ) ? 1 : 0;
    my $loggedin_hasjournal = ( $loggedin && !$u->is_identity ) ? 1 : 0;
    my $loggedin_canjoincomms = ( $loggedin && $u->is_person ) ? 1 : 0;   # note the semantic difference
    my $loggedin_hasnetwork = ( $loggedin && $u->can_use_network_page ) ? 1 : 0;
    my $loggedin_ispaid = ( $loggedin && $u->is_paid ) ? 1 : 0;
    my $loggedout = $loggedin ? 0 : 1;
    my $always = 1;
    my $never = 0;

    my @nav = (
        {
            name => 'create',
            items => [
                {
                    url => "$LJ::SITEROOT/create",
                    text => "menunav.create.createaccount",
                    display => $loggedout,
                },
                {
                    url => "$LJ::SITEROOT/manage/settings/?cat=display",
                    text => "menunav.create.displayprefs",
                    display => $loggedout,
                },
                {
                    url => "$LJ::SITEROOT/update",
                    text => "menunav.create.updatejournal",
                    display => $loggedin_hasjournal,
                },
                {
                    url => "$LJ::SITEROOT/editjournal",
                    text => "menunav.create.editjournal",
                    display => $loggedin_hasjournal,
                },
                {
                    url => "$LJ::SITEROOT/manage/profile/",
                    text => "menunav.create.editprofile",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/editpics",
                    text => "menunav.create.uploaduserpics",
                    text_opts => { num => $userpic_count, max => $userpic_max },
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/community/create",
                    text => "menunav.create.createcommunity",
                    display => $loggedin_canjoincomms,
                },
            ],
        },
        {
            name => 'organize',
            items => [
                {
                    url => "$LJ::SITEROOT/manage/settings/",
                    text => "menunav.organize.manageaccount",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/manage/circle/edit",
                    text => "menunav.organize.managerelationships",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/manage/circle/editfilters",
                    text => "menunav.organize.managefilters",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/manage/tags",
                    text => "menunav.organize.managetags",
                    display => $loggedin_hasjournal,
                },
                {
                    url => "$LJ::SITEROOT/community/manage",
                    text => "menunav.organize.managecommunities",
                    display => $loggedin_canjoincomms,
                },
                {
                    url => "$LJ::SITEROOT/tools/importer",
                    text => "menunav.organize.importcontent",
                    display => $loggedin_hasjournal,
                },
                {
                    url => "$LJ::SITEROOT/customize/",
                    text => "menunav.organize.selectstyle",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/customize/options",
                    text => "menunav.organize.customizestyle",
                    display => $loggedin,
                },
            ],
        },
        {
            name => 'read',
            items => [
                {
                    url => $u ? $u->journal_base . "/read" : "",
                    text => "menunav.read.readinglist",
                    display => $loggedin,
                },
                {
                    url => $u ? $u->profile_url : "",
                    text => "menunav.read.profile",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/syn/",
                    text => "menunav.read.syndicatedfeeds",
                    display => $loggedin,
                },
                {
                    url => $u ? $u->journal_base . "/tag" : "",
                    text => "menunav.read.tags",
                    display => $loggedin_hasjournal,
                },
                {
                    url => $u ? $u->journal_base . "/network" : "",
                    text => "menunav.read.network",
                    display => $loggedin_hasnetwork,
                },
                {
                    url => "$LJ::SITEROOT/tools/recent_comments",
                    text => "menunav.read.recentcomments",
                    display => $loggedin,
                },
                {
                    url => "$LJ::SITEROOT/inbox/",
                    text => $inbox_count ? "menunav.read.inbox.unread" : "menunav.read.inbox.nounread",
                    text_opts => { num => $inbox_count },
                    display => $loggedin,
                },
            ],
        },
        {
            name => 'explore',
            items => [
                {   url => "$LJ::SITEROOT/interests",
                    text => "menunav.explore.interests",
                    display => $always,
                },
                {
                    url => "$LJ::SITEROOT/directorysearch",
                    text => "menunav.explore.directorysearch",
                    display => $always,
                },
                {
                    url => "$LJ::SITEROOT/search",
                    text => "menunav.explore.sitesearch",
                    display => @LJ::SPHINX_SEARCHD ? 1 : 0,
                },
                {
                    url => "$LJ::SITEROOT/random",
                    text => "menunav.explore.randomjournal",
                    display => $always,
                },
                {
                    url => "$LJ::SITEROOT/community/random",
                    text => "menunav.explore.randomcommunity",
                    display => $always,
                },
                {
                    url => "$LJ::SITEROOT/support/faq",
                    text => "menunav.explore.faq",
                    display => $always,
                },
            ],
        },
        {
            name => 'shop',
            items => [
                {
                    url => "$LJ::SITEROOT/shop",
                    text => "menunav.shop.paidtime",
                    display => LJ::is_enabled( 'payments' ) ? 1 : 0,
                },
		        {
                    url => "$LJ::SITEROOT/shop/history",
                    text => "menunav.shop.history",
                    display => LJ::is_enabled( 'payments' ) && $loggedin ? 1 : 0,
		        },
		        {
                    url => "$LJ::SITEROOT/shop/gifts",
                    text => "menunav.shop.gifts",
                    display => LJ::is_enabled( 'payments' ) && $loggedin ? 1 : 0,
                },
                {
                    url => "$LJ::SITEROOT/shop/randomgift",
                    text => "menunav.shop.sponsor",
                    display => LJ::is_enabled( 'payments' ) ? 1 : 0,
                },
            ],
        },
    );

    return \@nav;
}

1;
