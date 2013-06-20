#!/usr/bin/perl
#
# DW::Media
#
# Base module for handling media storage and retrieval.  Media is defined as
# some item (document, photo, video, audio, etc) that is owned by a user,
# may be tagged, sorted, and secured.
#
# This is the base/generic media class, there are other classes.
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

package DW::Media;

use strict;
use Carp qw/ croak confess /;
use File::Type;
use Image::Size;

use DW::Media::Photo;

use constant TYPE_PHOTO => 1;

sub new {
    my ( $class, %opts ) = @_;
    confess 'Need a user and mediaid key'
        unless $opts{user} && LJ::isu( $opts{user} ) && $opts{mediaid};

    my $hr = $opts{user}->selectrow_hashref(
        q{SELECT userid, mediaid, anum, ext, state, mediatype, security, allowmask,
            logtime, mimetype, filesize
          FROM media WHERE userid = ? AND mediaid = ?},
        undef, $opts{user}->id, $opts{mediaid}
    );
    return if $opts{user}->err || ! $hr;

    # Calculate displayid here so it ends up in the object early.
    $hr->{displayid} = $hr->{mediaid} * 256 + $hr->{anum};

    # Set version to the original, since we always load that by default.
    $hr->{versionid} = $hr->{mediaid};

    # Metadata information, including height and width for a given image and
    # all of the alternates we have.
    my $vers = $opts{user}->selectall_hashref(
        q{SELECT versionid, height, width, filesize
          FROM media_versions WHERE userid = ? AND mediaid = ?},
        'versionid', undef, $opts{user}->id, $opts{mediaid}
    );
    return if $opts{user}->err || ! $vers;

    # Photo types can be instantiated and also support height and width.
    if ( $hr->{mediatype} == TYPE_PHOTO ) {
        my $self = DW::Media::Photo->new_from_row( %$hr, versions => $vers,
                height => $opts{height}, width => $opts{width} )
            or croak 'Failed to construct a photo object.';
        return $self;
    }

    croak 'Got an invalid row, or a type we do not support yet.';
}

sub upload_media {
    my ( $class, %opts ) = @_;
    confess 'Need a user key'
        unless $opts{user} && LJ::isu( $opts{user} );
    confess 'Need a file key or data key'
        unless $opts{file} && -e $opts{file} || $opts{data};

    # we need a mogilefs client or we can't store media
    my $mog = LJ::mogclient()
        or croak 'Sorry, MogileFS is not currently available.';

    # okay, we know who it's for and what it is, that's all we really need.
    if ( $opts{file} ) {
        open FILE, "<$opts{file}"
            or croak "Unable to load file to store.";
        { local $/ = undef; $opts{data} = <FILE>; }
        close FILE;
    }
    my $size = length $opts{data};

    # if no data then die
    croak 'Found no data to store.' unless $opts{data};

    # get type of file
    my $mime = File::Type->new->mime_type( $opts{data} )
        or croak 'Unable to get MIME-type for uploaded file.';

    # now get what type this is, from allowed mime types
    my ( $type, $ext ) = DW::Media->get_upload_type( $mime );
    croak 'Sorry, that file type is not currently allowed.'
        unless $type && $ext;

    # Now get the size information for this file, and fail if we can't
    my ( $width, $height ) = Image::Size::imgsize( \$opts{data} );
    croak 'Sorry, unable to get the image size.'
        unless defined $width && $width > 0 && defined $height && $height > 0;

    # set the security
    my $sec = $opts{security} || 'public';
    croak 'Invalid security for uploaded file.'
        unless $sec =~ /^(?:public|private|usemask)$/;
    $opts{allowmask} = 0 unless defined $opts{allowmask} && $sec eq 'usemask';

    # now we can cook -- allocate an id and upload
    my $id = LJ::alloc_user_counter( $opts{user}, 'A' )
        or croak 'Unable to allocate user counter for uploaded file.';
    $opts{user}->do(
        q{INSERT INTO media (userid, mediaid, anum, ext, state, mediatype, security, allowmask,
            logtime, mimetype, filesize) VALUES (?, ?, ?, ?, 'A', ?, ?, ?, UNIX_TIMESTAMP(), ?, ?)},
        undef, $opts{user}->id, $id, int(rand(256)), $ext, $type, $sec, $opts{allowmask},
        $mime, $size
    );
    croak "Failed to insert media row: " . $opts{user}->errstr . "."
        if $opts{user}->err;

    $opts{user}->do(
        q{INSERT INTO media_versions (userid, mediaid, versionid, width, height, filesize)
          VALUES (?, ?, ?, ?, ?, ?)},
        undef, $opts{user}->id, $id, $id, $width, $height, $size
    );
    croak "Failed to insert version row: " . $opts{user}->errstr . "."
        if $opts{user}->err;

    # now get this back as an object
    my $obj = DW::Media->new( user => $opts{user}, mediaid => $id );

    # now we have to stick this in MogileFS
    # FIXME: have different MogileFS classes for different media types
    my $fh = $mog->new_file( $obj->mogkey, 'media' )
        or croak 'Unable to instantiate file in MogileFS.'; # FIXME: nuke the row!
    $fh->print( $opts{data} );
    $fh->close
        or croak 'Unable to save file to MogileFS.'; # FIXME: nuke the row!

    # uploaded, so return an object for this item
    return $obj;
}

sub get_upload_type {
    my ( $class, $mime ) = @_;

    # FIXME: This may not cover everything. :-)
    return (TYPE_PHOTO, 'jpg') if $mime eq 'image/jpeg';
    return (TYPE_PHOTO, 'gif') if $mime eq 'image/gif';
    return (TYPE_PHOTO, 'png') if $mime eq 'image/png' || $mime eq 'image/x-png';

    return (undef, undef);
}

sub get_active_for_user {
    my ( $class, $u ) = @_;
    confess 'Invalid user' unless LJ::isu( $u );

    # get all active rows for this user
    my $rows = $u->selectcol_arrayref(
        q{SELECT mediaid FROM media WHERE userid = ? AND state = 'A'},
        undef, $u->id
    );
    croak 'Failed to select rows: ' . $u->errstr . '.' if $u->err;
    return () unless $rows && ref $rows eq 'ARRAY';

    # construct media objects for each of the items and return that
    return sort { $b->logtime <=> $a->logtime }
           map { DW::Media->new( user => $u, mediaid => $_ ) } @$rows;
}


1;
