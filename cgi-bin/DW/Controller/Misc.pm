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
use DW::Routing::Apache2;
use DW::Template::Apache2;

DW::Routing::Apache2->register_string( '/misc/whereami', \&whereami_handler, app => 1 );

# redirects the user to the login page to handle that eventuality
sub needlogin {
    my $r = DW::Request->get;

    my $uri = $r->uri;
    if ( my $qs = $r->query_string ) {
        $uri .= '?' . $qs;
    }
    $uri = LJ::eurl( $uri );

    $r->header_out( Location => "$LJ::SITEROOT/?returnto=$uri" );
    return $r->REDIRECT;
}

# returns an error page using a language string
sub error_ml {
    return DW::Template::Apache2->render_template(
        DW::Request->get->r, 'error.tt', { message => LJ::Lang::ml( $_[0] ) }
    );
}

# handles the /misc/whereami page
sub whereami_handler {
    my $r = DW::Request->get;

    my $remote = LJ::get_remote()
        or return needlogin();
    my $u = LJ::get_authas_user( $r->get_args->{authas} || $remote->user )
        or return error_ml( 'error.invalidauth' );

    my $vars = {
        user         => $u,
        cluster_name => $LJ::CLUSTER_NAME{$u->clusterid} || LJ::Lang::ml( '.cluster.unknown' ),
        authas_html  => LJ::make_authas_select( $remote, { authas => $u->user } ),
    };

    return DW::Template::Apache2->render_template(
        $r->r, 'misc/whereami.tt', $vars, {}
    );
}

1;
