#!/usr/bin/perl
#
# DW::Controller::Misc
#
# This controller is for miscellaneous, tiny pages that don't have much in the
# way of actions.  Things that aren't hard to do and can be done in 10-20 lines.
# If the page you want to create is bigger, please consider creating its own
# file to house it.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Misc;

use strict;
use warnings;
use DW::Controller;
use DW::Routing::Apache2;
use DW::Template::Apache2;

DW::Routing::Apache2->register_string( '/misc/whereami', \&whereami_handler, app => 1 );
DW::Routing::Apache2->register_string( '/pubkey',        \&pubkey_handler,   app => 1 );

# handles the /misc/whereami page
sub whereami_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $vars = { %$rv,
        cluster_name => $LJ::CLUSTER_NAME{$rv->{u}->clusterid} || LJ::Lang::ml( '.cluster.unknown' ),
    };

    return DW::Template::Apache2->render_template( 'misc/whereami.tt', $vars );
}

# handle requests for a user's public key
sub pubkey_handler {
    return error_ml( '.error.notconfigured' ) unless $LJ::USE_PGP;

    my ( $ok, $rv ) = controller( anonymous => 1, specify_user => 1 );
    return $rv unless $ok;

    LJ::load_user_props( $rv->{u}, 'public_key' );

    return DW::Template::Apache2->render_template( 'misc/pubkey.tt', $rv );
}

1;
