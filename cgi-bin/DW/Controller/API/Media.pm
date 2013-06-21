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
use LJ::JSON;

DW::Routing->register_api_endpoints(
        [ '/file/edit',   \&file_edit_handler,   1 ],
        [ '/file/new',    \&file_new_handler,    1 ],
        [ '/file/upload', \&file_upload_handler, 1 ],
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

# Used when requesting an id for a new file. Allocates a unique media ID and
# returns it for use in the upload handler.
sub file_new_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r = $rv->{r};
    LJ::isu( $rv->{u} )
        or return api_error( $r->HTTP_UNAUTHORIZED, 'Not logged in' );
    my $id = LJ::alloc_user_counter( $rv->{u}, 'A' )
        or return api_error( $r->SERVER_ERROR, 'Failed to allocate counter' );

    # FIXME: rate limit users so they can't spin the counter (it's per-user,
    # so they only hurt themselves, but why let it?)

    return api_ok( { id => $id } );
}

# Allows uploading a file. You give us the ID and file contents. You must have
# called /api/file/new first to get an upload ID.
sub file_upload_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    return api_ok( 1 );
}

# Allows editing the metadata and security on a media object.
sub file_edit_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    return api_ok( 1 );

}

1;
