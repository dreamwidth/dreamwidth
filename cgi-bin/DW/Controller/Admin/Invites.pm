#!/usr/bin/perl
#
# DW::Controller::Admin::Invites
#
# Management tasks related to invite codes.
# Requires finduser:codetrace, siteadmin:invites, or payments privileges.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::Invites;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

my $invite_privs =
    [ 'finduser:codetrace', 'finduser:*', 'payments', 'siteadmin:invites', 'siteadmin:*' ];

DW::Routing->register_string( "/admin/invites", \&index_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'invites',
    ml_scope => '/admin/invites/index.tt',
    privs    => $invite_privs
);

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => $invite_privs );
    return $rv unless $ok;
    my $remote = $rv->{remote};

    # we show links to various subpages depending on which privs the remote has;
    # can_manage_invites_light consists of "payments" or "siteadmin:invites"

    my $vars = {
        has_payments => $remote->has_priv("payments"),
        has_finduser => $remote->has_priv( "finduser", "codetrace" ),
        has_invites  => $remote->can_manage_invites_light,
    };

    return DW::Template->render_template( 'admin/invites/index.tt', $vars );
}

1;
