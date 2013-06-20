#!/usr/bin/perl
#
# DW::Media::Photo
#
# Special module for photos for the DW media system.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Media::Photo;

use strict;
use Carp qw/ croak confess /;

use DW::Media::Base;
use base 'DW::Media::Base';

sub new_from_row {
    my ( $class, %opts ) = @_;
    $opts{versions} ||= {};

    # We might be given an optional width and height parameters, which aren't
    # part of our basic object.
    my ( $width, $height ) = ( delete $opts{width}, delete $opts{height} );
    my $self = bless \%opts, $class;

    # Now pull out width and height for the default version.
    foreach my $vid ( keys %{$self->{versions}} ) {
        if ( $vid == $self->id ) {
            $self->{width} = $self->{versions}->{$vid}->{width};
            $self->{height} = $self->{versions}->{$vid}->{height};
            last;
        }
    }

    # Now, if given a width and height, select for it.
    $self->_select_version( width => $width, height => $height )
        if defined $width && defined $height;
    return $self;
}

sub _resize {
    my ( $self, %opts ) = @_;
    my ( $want_width, $want_height ) =
        ( delete $opts{width}, delete $opts{height} );
    return unless defined $want_width && defined $want_height;

    # Do not allow resizing of scaled images.
    croak 'Attempted to resize already resized image.'
        if $self->{mediaid} != $self->{versionid};

    # We evaluate this so that we only load Image::Magick in the context that
    # we need to use it. Saves us from loading it on webservers.
    eval "use Image::Magick (); 1;"
        or croak 'Failed to load Image::Magick for resize.';

    # Allocate new version ID.
    my $versionid = LJ::alloc_user_counter( $self->u, 'A' )
        or croak 'Failed to allocate version id for media resize.';

    # Scale the sizes.
    my ( $width, $height ) = ( $self->{width}, $self->{height} );
    my ( $horiz_ratio, $vert_ratio ) = ( $want_width / $width,
            $want_height / $height );
    my $ratio = $horiz_ratio < $vert_ratio ? $horiz_ratio : $vert_ratio;
    ( $width, $height ) = ( $width * $ratio, $height * $ratio );
    # FIXME: check off-by-one errors?

    # Load the image data, then scale it.
    my $dataref = LJ::mogclient()->get_file_data( $self->mogkey );
    my $timage = Image::Magick->new()
        or croak 'Failed to instantiate Image::Magick object.';
    $timage->BlobToImage( $$dataref );
    $timage->Scale( width => $width, height => $height );
    my $blob = $timage->ImageToBlob;

    # Fix up this object's internal representation.
    $self->{versionid} = $versionid;
    $self->{width} = $timage->Get( 'width' );
    $self->{height} = $timage->Get( 'height' );
    $self->{filesize} = length $blob;

    # Now save to MogileFS first, before adding it to the database.
    my $fh = LJ::mogclient()->new_file( $self->mogkey, 'media' )
        or croak 'Unable to instantiate resized file in MogileFS.';
    $fh->print( $blob ); # Aww, deref...
    $fh->close
        or croak 'Unable to save resized file to MogileFS.';

    # Insert into the database, then we're done.
    my $u = $self->u;
    $u->do(
        q{INSERT INTO media_versions (userid, mediaid, versionid, height, width, filesize)
          VALUES (?, ?, ?, ?, ?, ?)},
        undef, $self->{userid}, $self->{mediaid}, $versionid, $self->{height},
        $self->{width}, $self->{filesize}
    );
    croak $u->errstr if $u->err;

    return $self;
}

# Requires both width and height.
sub _select_version {
    my ( $self, %opts ) = @_;
    my ( $want_width, $want_height ) =
        ( delete $opts{width}, delete $opts{height} );
    return unless defined $want_width && defined $want_height;

    # Ensure no extra options (mostly, makes sure this code gets updated if
    # someone wants to add extra stuff).
    croak 'Extra options to _select_version.' if %opts;

    my ( $width, $height ) = ( $self->{width}, $self->{height} );
    croak 'Image has no internal width/height!' # Should never fire...
        unless defined $width && $width > 0 && defined $height && $height > 0;

    # If we want larger than we are (and this is the original), accept it.
    return if $want_width >= $width && $want_height >= $height;

    # We have a simple algorithm: we look at our existing versions and try to
    # find one that has an edge match where the other side is within bounds. If
    # that is true, we trust it and return it.
    foreach my $vid ( keys %{$self->{versions}} ) {
        my ( $ver_width, $ver_height ) = ( $self->{versions}->{$vid}->{width},
            $self->{versions}->{$vid}->{height} );

        if ( ( $ver_width == $want_width && $ver_height <= $want_height ) ||
            ( $ver_height == $want_height && $ver_width <= $want_width ) )
        {
            $self->{versionid} = $vid;
            $self->{$_} = $self->{versions}->{$vid}->{$_}
                foreach qw/ width height filesize /;
            return;
        }
    }

    # No version found... so now we want to kick off a Gearman job to do the
    # resize for us. FIXME: This is inline for now.
    croak 'Failed to resize.'
        unless $self->_resize( width => $want_width, height => $want_height );

    # The _resize call also updates our internal data, so this image is now
    # the resized image.
}

1;
