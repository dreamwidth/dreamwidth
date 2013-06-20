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

my %VALID_SIZES = ( map { $_ => 1 } ( 320, 200, 640, 480, 1024, 768, 1280,
            800, 600, 720, 1600, 1200 ) );

DW::Routing->register_regex( qr!^/file/(\d+)$!, \&media_handler, user => 1, formats => 1 );
DW::Routing->register_regex( qr!^/file/(\d+x\d+|full)(/\w:[\d\w]+)*/(\d+)$!,
        \&media_handler, user => 1, formats => 1 );
DW::Routing->register_string( '/file/list', \&media_manage_handler, app => 1 );
DW::Routing->register_string( '/file/edit', \&media_bulkedit_handler, app => 1 );

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

    my @security = (
            { value => "public",  text => LJ::Lang::ml( 'label.security.public2' ) },
            { value => "usemask",  text => LJ::Lang::ml( 'label.security.accesslist' ) },
            { value => "private", text => LJ::Lang::ml( 'label.security.private2' ) },
        );
    $rv->{security} = \@security;

    my $r = DW::Request->get;
    if ( $r->did_post ) {
        my $post_args = $r->post_args;
        return error_ml( 'error.invalidauth' ) unless LJ::check_form_auth( $post_args->{lj_form_auth} );

        if ( $post_args->{"action:edit"} ) {
            my %post = %{$post_args->as_hashref||{}};
            while ( my ($key, $secval) = each %post ) {
                next unless $key =~ m/^security-(\d+)/;
                my $mediaid = $1 >> 8;
                my $media = DW::Media->new( user => $rv->{u}, mediaid => $mediaid );
                next unless $media;

                my $amask = $secval eq "usemask" ? 1 : 0;
                $media->set_security( security => $secval, allowmask => $amask );
            }
        } elsif ( $post_args->{"action:delete"} ) {
            # FIXME: update with more efficient mass loader
            my @to_delete = $post_args->get_all( "delete" );
            foreach my $id ( @to_delete ) {
                # FIXME: error messages
                my $mediaid = $id >> 8;
                my $media = DW::Media->new( user => $rv->{u}, mediaid => $mediaid );
                next unless $media;

                $media->delete;
            }
        }
    }

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

    # Old format or new format detection
    my ( $size, $extra, $id ) = @{$opts->subpatterns};
    my ( $width, $height );
    if ( $size =~ /^(\d+)x(\d+)$/ ) {
        ( $width, $height ) = ( $1, $2 );
    } elsif ( $size eq 'full' ) {
        # Do nothing, leave width/height undef
    } elsif ( $size =~ /^\d+$/ ) {
        # Should be old style format, so let's assume
        ( $id, $size, $extra ) = ( $size + 0, undef, undef );
    } else {
        return $error_out->( 404, 'Not found' );
    }

    # Ensure if a width or height are given, BOTH are given
    return $error_out->( 404, 'Not found' )
        if defined $width xor defined $height;

    # Constrain widths and heights to certain valid sets
    if ( defined $width ) {
        return $error_out->( 404, 'Not found' )
            unless exists $VALID_SIZES{$width} &&
                   exists $VALID_SIZES{$height};
    }

    # Finalize id and extension checking
    my $ext = $opts->{format};
    return $error_out->( 404, 'Not found' )
        unless $id && $ext;
    my $anum = $id % 256;
    $id = ($id - $anum) / 256;

    # Load the account or error
    return $error_out->( 404, 'Need account name as user parameter' )
        unless $opts->username;
    my $u = LJ::load_user_or_identity( $opts->username )
        or return $error_out->( 404, 'Invalid account' );

    # try to get the media object
    my $obj = DW::Media->new( user => $u, mediaid => $id,
            width => $width, height => $height )
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
