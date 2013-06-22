#!/usr/bin/perl
#
# DW::Controller::API::Media
#
# API controls for the media system.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::Media;

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use DW::Controller::API;
use DW::Media;
use LJ::JSON;

DW::Routing->register_api_endpoints(
        [ '/file/edit',   \&file_edit_handler,   1 ],
        [ '/file/new',    \&file_new_handler,    1 ],
);

#{
#  files:
#    [
#      {
#        url: "http://url.to/file/or/page",
#        thumbnail_url: "http://url.to/thumnail.jpg",
#        name: "thumb2.jpg",
#        type: "image/jpeg",
#        size: 46353,
#OPT        delete_url: "http://url.to/delete/file/",
#OPT        delete_type: "DELETE"
#      }
#    ]
#}

# Allows uploading a file. Allocates and returns a unique media ID for the upload.
sub file_new_handler {
    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    $r->did_post
        or return api_error( $r->HTTP_METHOD_NOT_ALLOWED, 'Needs a POST request' );

    LJ::isu( $rv->{u} )
        or return api_error( $r->HTTP_UNAUTHORIZED, 'Not logged in' );

    my $uploads = $r->uploads;
    return api_error( $r->HTTP_BAD_REQUEST, 'No uploads found' )
        unless ref $uploads eq 'ARRAY' && scalar @$uploads;

    foreach my $upload ( @$uploads ) {
        my ( $type, $ext ) = DW::Media->get_upload_type( $upload->{'content-type' } );
        next unless $type == DW::Media::TYPE_PHOTO;

        # Try to upload this item since we know it's a photo.
        my $obj = DW::Media->upload_media(
            user     => $rv->{u},
            data     => $upload->{body},
            security => $rv->{u}->newpost_minsecurity,
        );
        return api_error( $r->SERVER_ERROR, 'Failed to upload media' )
            unless $obj;

        # For now, we only support a single upload per call, so finish now.
        return api_ok( {
            id => $obj->id,
            url => $obj->url,
            thumbnail_url => $obj->url( extra => '100x100/' ),
            name => "image",
            type => $obj->mimetype,
            size => $obj->size,
        } );
    }

    return api_error( $r->HTTP_BAD_REQUEST, 'No uploads found' );
}

# Allows editing the metadata and security on a media object.
sub file_edit_handler {
    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    $r->did_post
        or return api_error( $r->HTTP_METHOD_NOT_ALLOWED, 'Needs a POST request' );

    LJ::isu( $rv->{u} )
        or return api_error( $r->HTTP_UNAUTHORIZED, 'Not logged in' );

    return api_ok( 1 );

}

1;
