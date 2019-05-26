#!/usr/bin/perl
#
# DW::Controller::Interface::Flat
#
# This controller is for the old flat interface
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Interface::Flat;

use strict;
use DW::Routing;

DW::Routing->register_string(
    '/interface/flat', \&interface_handler,
    app     => 1,
    format  => 'plain',
    methods => { GET => 1, POST => 1 }
);

sub interface_handler {
    my $r = DW::Request->get;

    my ( %out, %post );

    my $post_args = $r->post_args;
    %post = %{ $post_args->as_hashref } if $post_args;

    LJ::do_request( \%post, \%out );

    if ( "urlenc" eq ( $post{responseenc} || "" ) ) {
        foreach ( sort keys %out ) {
            $r->print( LJ::eurl($_) . "=" . LJ::eurl( $out{$_} ) . "&" );
        }
        return $r->OK;
    }

    my $length = 0;
    foreach ( sort keys %out ) {
        $length += length($_) + 1;
        $length += length( $out{$_} ) + 1;
    }
    $r->header_out( "Content-Length", $length );

    foreach ( sort keys %out ) {
        my $key = $_;
        my $val = $out{$_};
        $key =~ y/\r\n//d;
        $val =~ y/\r\n//d;
        $r->print( $key, "\n", $val, "\n" );
    }

    return $r->OK;
}

1;
