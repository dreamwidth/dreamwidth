#!/usr/bin/perl
#
# DW::Controller::API::Media
#
# API controls for the media system.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013-2018 by Dreamwidth Studios, LLC.
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

    return api_error( $r->HTTP_UNAUTHORIZED, 'Invalid account type' )
        if $rv->{u}->is_identity;

    return api_error( $r->HTTP_BAD_REQUEST, 'Quota exceeded' )
        unless DW::Media->can_upload_media( $rv->{u} );

    my $uploads = $r->uploads;
    return api_error( $r->HTTP_BAD_REQUEST, 'No uploads found' )
        unless ref $uploads eq 'ARRAY' && scalar @$uploads;

    foreach my $upload ( @$uploads ) {
        my ( $type, $ext ) = DW::Media->get_upload_type( $upload->{'content-type' } );
        next unless defined $type && $type == DW::Media::TYPE_PHOTO;

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
            id => $obj->displayid,
            url => $obj->url,
            thumbnail_url => $obj->url( extra => '100x100/' ),
            name => "image",
            type => $obj->mimetype,
            size => $obj->size,
        } );
    }

    return api_error( $r->HTTP_BAD_REQUEST, 'No uploads found' );
}

# Allows editing the metadata and security on a media object. The input to this
# function is a dict, keys are the ids to modify, and the value is another dict
# that contains what to modify. Example:
#
#  {
#     1234: {
#         security => "public",  # public, private, access, usemask
#         allowmask => 3553,     # only valid in usemask security
#         title => "some title", # else, the name of the property
#         otherprop => 5,
#         ...
#     }
#     5653: ...
#  }
#
sub file_edit_handler {
    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    $r->did_post
        or return api_error( $r->HTTP_METHOD_NOT_ALLOWED, 'Needs a POST request' );

    LJ::isu( $rv->{u} )
        or return api_error( $r->HTTP_UNAUTHORIZED, 'Not logged in' );

    my $args = $r->json
        or return api_error( $r->HTTP_BAD_REQUEST, 'Invalid/no JSON input' );

    # First pass to check arguments.
    my %media;
    foreach my $id ( keys %$args ) {
        # sometimes JS sends us the string 'null' so let's make sure $id is OK
        return api_error( $r->HTTP_BAD_REQUEST, 'Media ID not provided' )
            unless defined $id && $id ne 'null';

        # use eval to catch croaks
        $media{$id} = eval { DW::Media->new( user => $rv->{u},
                                             mediaid => int( $id / 256 ) ) };
        return api_error( $r->NOT_FOUND, 'Media ID not found or invalid' )
            unless $media{$id};

        return api_error( $r->HTTP_BAD_REQUEST, 'Security invalid' )
            if $args->{$id}->{security} &&
               $args->{$id}->{security} !~ /^(?:public|private|usemask)$/;
        if ( exists $args->{$id}->{allowmask} ) {
            return api_error( $r->HTTP_BAD_REQUEST, 'Allowmask invalid with chosen security' )
                unless $args->{$id}->{security} eq 'usemask';
            return api_error( $r->HTTP_BAD_REQUEST, 'Allowmask must be numeric' )
                unless $args->{$id}->{allowmask} =~ /^\d+$/;
        }

        # Check to be sure this is valid. Security and Allowmask are separate
        # from the rest, which are properties.
        foreach my $key ( keys %{$args->{$id}} ) {
            next if $key eq 'security' || $key eq 'allowmask';

            my $pobj = LJ::get_prop( media => $key );
            return api_error( $r->HTTP_BAD_REQUEST, 'Invalid property' )
                unless ref $pobj eq 'HASH' && $pobj->{id};
        }
    }

    # We did that in two phases so we could verify that all of the objects
    # were loadable, to try to make it an atomic process.
    foreach my $id ( keys %$args ) {
        my ( $security, $allowmask ) = ( delete $args->{$id}->{security},
            int( delete $args->{$id}->{allowmask} // 0 ) );
        if ( defined $security ) {
            $media{$id}->set_security(
                security  => $security,
                allowmask => $allowmask,
            );
        }

        # At this point, we must have deleted all non-property items.
        foreach my $prop ( keys %{$args->{$id}} ) {
            $media{$id}->prop( $prop => $args->{$id}->{$prop} );
        }
    }

    return api_ok( $args );
}

1;
