#!/usr/bin/perl
#
# DW::Controller::VGift
#
# Serves virtual gift image data. Replaces the Apache::LiveJournal vgift handler
# for use under both Plack and mod_perl via DW::Routing.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::VGift;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::BlobStore;
use DW::Request;
use DW::Routing;
use DW::VirtualGift;

DW::Routing->register_regex( qr!^/vgift/(\d+)/(small|large)$!, \&vgift_handler, app => 1 );

sub vgift_handler {
    my ($opts) = @_;
    my $r = DW::Request->get;

    my ( $picid, $picsize ) = @{ $opts->subpatterns };

    # IMS is valid unless the request is coming from the admin interface
    my $referer = $r->header_in('Referer') || '';
    if ( $r->header_in('If-Modified-Since') && $referer !~ m!^\Q$LJ::SITEROOT\E/admin/! ) {
        $r->status(304);
        return $r->OK;
    }

    my $vg   = DW::VirtualGift->new($picid);
    my $mime = $vg->mime_type($picsize)
        or return $r->NOT_FOUND;

    my $key  = $vg->img_mogkey($picsize);
    my $data = DW::BlobStore->retrieve( vgifts => $key )
        or return $r->NOT_FOUND;

    $r->content_type($mime);
    $r->header_out( 'Content-Length' => length $$data );
    $r->header_out( 'Cache-Control'  => 'no-transform' );
    $r->print($$data);

    return $r->OK;
}

1;
