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
use Image::Magick;
use Image::ExifTool qw/ :Public /;

use DW::BlobStore;

use DW::Media::Base;
use base 'DW::Media::Base';

sub new_from_row {
    my ( $class, %opts ) = @_;
    $opts{versions} ||= {};

    # We might be given an optional width and height parameters, which aren't
    # part of our basic object.
    my ( $width, $height ) = ( delete $opts{width}, delete $opts{height} );
    my $self = bless \%opts, $class;

    # Save the URL width/height, since we'll need that for later.
    $self->{url_width}  = $width;
    $self->{url_height} = $height;

    # Now pull out width and height for the default version.
    foreach my $vid ( keys %{ $self->{versions} } ) {
        if ( $vid == $self->id ) {
            $self->{width}  = $self->{versions}->{$vid}->{width};
            $self->{height} = $self->{versions}->{$vid}->{height};

            # save the original values of these for reference in case we resize later
            $self->{orig_width}    = $self->{width};
            $self->{orig_height}   = $self->{height};
            $self->{orig_filesize} = $self->{filesize};
            last;
        }
    }

    # Now, if given a width and height, select for it.
    $self->_select_version( width => $width, height => $height )
        if defined $width && defined $height;
    return $self;
}

# Called with the file extension (one of our well known file types) and a
# reference to the image data, which is updated if necessary.
sub preprocess {
    my ( $class, $ext, $dataref ) = @_;

    # For now, we only care about jpegs since they need to be reoriented.
    return unless $ext eq 'jpg';

    # Extract EXIF orientation data to calculate our operations.
    my $timage = Image::Magick->new()
        or croak 'Failed to instantiate Image::Magick object.';
    $timage->BlobToImage($$dataref);
    $timage->AutoOrient();
    $$dataref = $timage->ImageToBlob;

    # The orientation should now be reset to 1 to prevent browser rotating.
    my $exif = Image::ExifTool->new;
    $exif->SetNewValue( Orientation => 1, Type => 'Raw' );
    $exif->WriteInfo($dataref);
}

sub _resize {
    my ( $self, %opts ) = @_;
    my ( $want_width, $want_height ) =
        ( delete $opts{width}, delete $opts{height} );
    return unless defined $want_width && defined $want_height;

    # Do not allow resizing of scaled images.
    croak 'Attempted to resize already resized image.'
        if $self->{mediaid} != $self->{versionid};

    # Allocate new version ID.
    my $versionid = LJ::alloc_user_counter( $self->u, 'A' )
        or croak 'Failed to allocate version id for media resize.';

    # Scale the sizes.
    my ( $width, $height ) = ( $self->{width}, $self->{height} );
    my ( $horiz_ratio, $vert_ratio ) = ( $want_width / $width, $want_height / $height );
    my $ratio = $horiz_ratio < $vert_ratio ? $horiz_ratio : $vert_ratio;
    ( $width, $height ) = ( int( $width * $ratio + 0.5 ), int( $height * $ratio + 0.5 ) );

    # Load the image data, then scale it.
    my ( $username, $mediaid ) = ( $self->u->user, $self->{mediaid} );
    my $dataref = DW::BlobStore->retrieve( media => $self->mogkey )
        or croak "Failed to load image file $mediaid for $username.";
    my $timage = Image::Magick->new()
        or croak 'Failed to instantiate Image::Magick object.';
    $timage->BlobToImage($$dataref);
    $timage->Scale( width => $width, height => $height );
    my $blob = $timage->ImageToBlob;

    # Fix up this object's internal representation.
    $self->{versionid} = $versionid;
    $self->{width}     = $timage->Get('width');
    $self->{height}    = $timage->Get('height');
    $self->{filesize}  = length $blob;

    # Now save to file storage first, before adding it to the database.
    DW::BlobStore->store( media => $self->mogkey, \$blob )
        or croak 'Unable to save resized file to storage.';

    # Insert into the database, then we're done.
    my $u = $self->u;
    $u->do(
        q{INSERT INTO media_versions (userid, mediaid, versionid, height, width, filesize)
          VALUES (?, ?, ?, ?, ?, ?)},
        undef,          $self->{userid}, $self->{mediaid}, $versionid, $self->{height},
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
    croak 'Image has no internal width/height!'    # Should never fire...
        unless defined $width && $width > 0 && defined $height && $height > 0;

    # If we want larger than we are (and this is the original), accept it.
    return if $want_width >= $width && $want_height >= $height;

    # We have a simple algorithm: we look at our existing versions and try to
    # find one that has an edge match where the other side is within bounds. If
    # that is true, we trust it and return it.
    foreach my $vid ( keys %{ $self->{versions} } ) {
        my ( $ver_width, $ver_height ) =
            ( $self->{versions}->{$vid}->{width}, $self->{versions}->{$vid}->{height} );

        if (   ( $ver_width == $want_width && $ver_height <= $want_height )
            || ( $ver_height == $want_height && $ver_width <= $want_width ) )
        {
            $self->{versionid} = $vid;
            $self->{$_} = $self->{versions}->{$vid}->{$_} foreach qw/ width height filesize /;
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

# this adds on to the base method by also deleting any associated thumbnails
sub delete {
    my $self    = $_[0];
    my $deleted = $self->SUPER::delete;    # this deletes the original as before
    return 0 unless $deleted;              # was already deleted

    # at this point the image has just been deleted - look for thumbnails
    my $u  = $self->u or croak 'Sorry, unable to load the user.';
    my @mv = $u->selectrow_array(
        "SELECT versionid FROM media_versions WHERE userid=? AND mediaid=?" . " AND versionid != ?",
        undef, $u->id, $self->versionid, $self->versionid
    );

    return $deleted unless @mv;

    foreach my $id (@mv) {

        # create a fake object to get the mogkey
        my $fakeobj = bless { userid => $u->id, versionid => $id }, 'DW::Media::Photo';

        # we aren't concerned whether the file existed or not,
        # and the associated media row is already in a deleted state
        DW::BlobStore->delete( media => $fakeobj->mogkey );
    }

    return 1;    # done
}

1;
