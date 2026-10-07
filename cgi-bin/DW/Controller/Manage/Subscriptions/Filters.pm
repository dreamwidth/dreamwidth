#!/usr/bin/perl
#
# DW::Controller::Manage::Subscriptions::Filters
#
# Page to manage your subscription filters. The page is mostly a static
# shell driven by js/subfilters.js, which talks to the __rpc_contentfilters
# endpoint over AJAX.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Subscriptions::Filters;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/subscriptions/filters", \&filters_handler, app => 1 );

sub filters_handler {
    my ( $ok, $rv ) = controller( anonymous => 0 );
    return $rv unless $ok;

    # custom CSS/JS for the filter-editing interface
    LJ::set_active_resource_group('jquery');
    LJ::need_res( { priority => $LJ::OLD_RES_PRIORITY }, 'stc/subfilters.css' );
    LJ::need_res( { group => 'jquery' }, 'js/subfilters.js' );

    return DW::Template->render_template( 'manage/subscriptions/filters.tt', $rv );
}

1;
