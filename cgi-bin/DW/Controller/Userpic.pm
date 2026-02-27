#!/usr/bin/perl
#
# DW::Controller::Userpic
#
# Serves userpic image data. Replaces the Apache::LiveJournal userpic handler
# for use under both Plack and mod_perl via DW::Routing.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Userpic;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Routing;
use DW::Request;
use LJ::Userpic;

DW::Routing->register_regex( qr!^/userpic/(\d+)/(\d+)$!, \&userpic_handler, app => 1 );

sub userpic_handler {
    my ($opts) = @_;
    my $r = DW::Request->get;

    my ( $picid, $userid ) = @{ $opts->subpatterns };

    # We can safely return 304 without checking since we never re-use
    # picture IDs and don't let the contents get modified
    if ( $r->header_in('If-Modified-Since') ) {
        $r->status(304);
        return $r->OK;
    }

    # Load the user object and pic and make sure the picture is viewable
    my $u   = LJ::load_userid($userid);
    my $pic = LJ::Userpic->get( $u, $picid, { no_expunged => 1 } )
        or return $r->NOT_FOUND;

    # Must have contents by now, or return 404
    my $data = $pic->imagedata
        or return $r->NOT_FOUND;

    # Everything looks good, send it
    $r->content_type( $pic->mimetype );
    $r->header_out( 'Content-Length' => length $data );
    $r->header_out( 'Cache-Control'  => 'no-transform' );
    $r->header_out( 'Last-Modified'  => LJ::time_to_http( $pic->pictime ) );
    $r->print($data);

    return $r->OK;
}

1;
