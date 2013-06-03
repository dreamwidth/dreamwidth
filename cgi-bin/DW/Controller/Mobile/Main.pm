#!/usr/bin/perl
#
# DW::Controller::Mobile::Main
#
# Controls the main mobile entrance pages, such as login
# and index/navigation menus
#
# Authors:
#      foxfirefey <foxfirefey@gmail.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Mobile::Main;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use JSON;

DW::Routing->register_string( '/mobile', \&index_handler, app => 1 );

sub index_handler {
    my ( $opts ) = @_;
    my $r = DW::Request->get;

    my $vars = {
        'remote' => LJ::User->remote,
    };

    return DW::Template->render_template( 'mobile/index.tt', $vars, { 'no_sitescheme' => 1 } );
}

1;
