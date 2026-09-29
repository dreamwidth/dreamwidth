#!/usr/bin/perl
#
# DW::Controller::Journal::Protected
#
# Displays for an entry that doesn't exist or that the viewer can't see.
#
# Author:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2010-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Journal::Protected;

use strict;
use warnings;

use DW::Auth::Challenge;
use DW::Controller;
use DW::Template;
use DW::Routing;
use DW::Request;

DW::Routing->register_string( '/protected', \&protected_handler, app => 1 );

sub protected_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    # Same status as a missing entry, so the two can't be told apart (RFC 9110 15.5.4).
    $r->status(404);

    # returnto will either have been set as a request note or passed in as
    # a query argument.  if neither of those work, we can reconstruct it
    # using the current request url
    my $returnto = $r->note('returnto') || LJ::ehtml( $r->get_args->{returnto} );
    if ( ( !$returnto ) && ( $r->uri ne '/protected' ) ) {
        $returnto = LJ::ehtml( LJ::create_url( undef, keep_args => 1 ) );
    }

    my $vars = {
        returnto => $returnto,
        remote   => $rv->{remote},
        message  => $r->get_args->{posted} ? '.message.comment.posted' : '',
    };

    $vars->{chal} = DW::Auth::Challenge->generate(300) unless $rv->{remote};

    return DW::Template->render_template( 'error/unavailable.tt', $vars );

}

1;
