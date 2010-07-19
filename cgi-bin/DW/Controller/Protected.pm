#!/usr/bin/perl
#
# DW::Controller::Protected
#
# Displays when a user tries to access protected content.
#
# Author:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Protected;

use strict;
use warnings;
use DW::Controller;
use DW::Template;
use DW::Routing;
use DW::Request;

DW::Routing->register_string( '/protected', \&protected_handler, app => 1 );

sub protected_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    # set the status to 403
    $r->status( 403 );

    # returnto will either have been set as a request note or passed in as 
    # a query argument.  if neither of those work, we can reconstruct it
    # using the current request url
    my $returnto = $r->note( 'returnto' ) || LJ::ehtml( $r->get_args->{returnto} );
    if ( ( ! $returnto ) && ( $r->uri ne '/protected' ) ) {
        my $host = $r->header_in('Host');
        my $query_string = $r->query_string ? "?" . $r->query_string : "";
        $returnto = LJ::ehtml( "http://$host" . $r->uri . "$query_string" );
    }

    my $vars = {
        returnto => $returnto,
    };

    my $remote = $rv->{remote};

    if ( $remote ) {
        $vars->{remote} = $remote;
        if ( $r->note( 'error_key' ) ) {
            my $journalname = $r->note( 'journalname' );
            $vars->{journalname} = $journalname;
            $vars->{'error_key'} = '.protected.error.notauthorised' . $r->note( 'error_key' );
        } else {
            $vars->{'error_key'} = '.protected.message.user';
            $vars->{'journalname'} = "";
        }
    } else {
        $vars->{chal} = LJ::challenge_generate(300);
        # include SSL if it's an option
        $vars->{'usessl'} = $LJ::USE_SSL;
    }
    
    return DW::Template->render_template( 'protected.tt', $vars );

}

1;
