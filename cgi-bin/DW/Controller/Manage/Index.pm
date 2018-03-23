#!/usr/bin/perl
#
# DW::Controller::Manage::Index
#
# /manage/index
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Index;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/index", \&index_handler, app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $u = $rv->{u};  # authas || remote
    $u->preload_props( 'stylesys' );
    $u->{stylesys} ||= 2;

    $rv->{use_s2} = $u->{stylesys} == 2 ? 1 : 0;
    $rv->{use_pubkey} = $LJ::USE_PGP;
    $rv->{use_invites} = $LJ::USE_ACCT_CODES;
    $rv->{use_tags} = LJ::is_enabled('tags');

    return DW::Template->render_template( 'manage/index.tt', $rv );
}

1;
