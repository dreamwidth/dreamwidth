#!/usr/bin/perl
#
# DW::Controller::Media
#
# Displays media for a user.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Media;

use strict;
use warnings;
use DW::Routing;
use DW::Request;

use DW::Controller;

DW::Routing->register_regex( qr|^/media/(\d+)$|, \&media_handler, user => 1, formats => 1 );
DW::Routing->register_string( '/media', \&media_manage_handler, app => 1 );

DW::Routing->register_string( '/media/edit', \&media_bulkedit_handler, app => 1 );

sub media_manage_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    # load all of a user's media.  this is inefficient and won't be like this forever,
    # but it's simple for now...
    $rv->{media} = [ DW::Media->get_active_for_user( $rv->{remote} ) ];

    return DW::Template->render_template( 'media/index.tt', $rv );
}

sub media_bulkedit_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    $rv->{media} = [ DW::Media->get_active_for_user( $rv->{remote} ) ];

    return DW::Template->render_template( 'media/edit.tt', $rv );
}

sub media_handler {
    my $opts = shift;
    my $r = DW::Request->get;

    # Outputs an error message
    my $error_out = sub {
       my ( $code, $message ) = @_;
       $r->status( $code );
       return $r->NOT_FOUND if $code == 404;

       $r->print( $message );
       return $r->OK;
    };

    # get the media id
    my ( $id, $ext ) = ( $opts->subpatterns->[0], $opts->{format} );
    warn "$id $ext\n";
    $error_out->( 404, 'Not found' )
        unless $id && $ext;
    my $anum = $id % 256;
    $id = ($id - $anum) / 256;

    # Load the account or error
    return $error_out->(404, 'Need account name as user parameter')
        unless $opts->username;
    my $u = LJ::load_user_or_identity( $opts->username )
        or return $error_out->( 404, 'Invalid account' );

    # try to get the media object
    my $obj = DW::Media->new( user => $u, mediaid => $id )
        or return $error_out->( 404, 'Not found' );
    return $error_out->( 404, 'Not found' )
        unless $obj->is_active && $obj->anum == $anum && $obj->ext eq $ext;

    # access control
# FIXME: support viewall
    return $error_out->( 403, 'Not authorized' )
        unless $obj->visible_to( LJ::get_remote() );

    # load the data for this object
# FIXME: support X-REPROXY headers here
    my $dataref = LJ::mogclient()->get_file_data( $obj->mogkey );
    return $error_out->( 500, 'Unexpected internal error locating file' )
        unless defined $dataref && ref $dataref eq 'SCALAR';

    # now we're done!
    $r->content_type( $obj->mimetype );
    $r->print( $$dataref );
    return $r->OK;
}

1;
