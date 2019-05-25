#!/usr/bin/perl
#
# DW::Controller::Legal
#
# Controller for the /legal pages.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Legal;

use strict;
use warnings;

use DW::Routing;
use DW::Template;
use LJ::Hooks;

my @pages = qw( tos privacy );
LJ::Hooks::run_hook( 'modify_legal_index', \@pages );    # add nonfree pages
my $args = { index => [] };

foreach my $page (@pages) {

    # register the page view
    DW::Routing->register_static( "/legal/$page", "legal/$page.tt", app => 1 );

    # add the page to the index list
    push @{ $args->{index} }, { page => $page, header => ".$page-header", text => ".$page" };
}

# register the index view
DW::Routing->register_string( '/legal/index', \&index_handler, app => 1 );

sub index_handler {
    return DW::Template->render_template( 'legal/index.tt', $args );
}

1;
