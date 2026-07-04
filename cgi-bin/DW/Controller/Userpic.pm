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

    # Load the user object and pic up front. This has to happen before the
    # If-Modified-Since short-circuit below so a suspended pic can never be
    # answered with a 304 that reaffirms the client's cached (suspended) image.
    my $u   = LJ::load_userid($userid);
    my $pic = LJ::Userpic->get( $u, $picid, { no_expunged => 1 } );

    # Suspended (e.g. DMCA): serve the default icon in its place, never the
    # real bytes and never a 304.
    return _serve_default_userpic($r) if $pic && $pic->suspended;

    # Otherwise it's safe to 304 without loading the blob: we never re-use
    # picture IDs and don't let the contents get modified, so a client's cached
    # copy is always still valid.
    if ( $r->header_in('If-Modified-Since') ) {
        $r->status(304);
        return $r->OK;
    }

    # Must have a pic with contents by now, or return 404
    return $r->NOT_FOUND unless $pic;
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

# Bytes of the site default icon, read from disk once per worker.
my $DEFAULT_USERPIC;

sub _serve_default_userpic {
    my $r = $_[0];

    unless ( defined $DEFAULT_USERPIC ) {
        if ( open my $fh, '<:raw', "$LJ::HOME/htdocs/img/nouserpic.png" ) {
            local $/;
            $DEFAULT_USERPIC = <$fh>;
            close $fh;
        }
    }
    return $r->NOT_FOUND unless defined $DEFAULT_USERPIC;

    $r->content_type('image/png');
    $r->header_out( 'Content-Length' => length $DEFAULT_USERPIC );

    # Short TTL, and no real Last-Modified: the substituted default must not
    # linger in caches once the suspension is lifted.
    $r->header_out( 'Cache-Control' => 'max-age=300, no-transform' );
    $r->print($DEFAULT_USERPIC);

    return $r->OK;
}

1;
