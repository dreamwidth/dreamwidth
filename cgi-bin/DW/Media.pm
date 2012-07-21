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

    return DW::Media::Photo->new_from_row( %$hr )
        if $hr->{mediatype} == TYPE_PHOTO;

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

    # if no data then die
    croak 'Found no data to store.' unless $opts{data};

    # get type of file
    my $mime = File::Type->new->mime_type( $opts{data} )
        or croak 'Unable to get MIME-type for uploaded file.';

    # now get what type this is, from allowed mime types
    my ( $type, $ext ) = DW::Media->get_upload_type( $mime );
    croak 'Sorry, that file type is not currently allowed.'
        unless $type && $ext;

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
        $mime, length $opts{data}
    );
    croak "Failed to insert media row: " . $opts{user}->errstr . "."
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

# we delete the actual file
# but we keep the metadata around for record-keeping purpose
sub delete_media {
    my ( $class, %opts ) = @_;

    confess 'Need a user key'
        unless $opts{user} && LJ::isu( $opts{user} );

    my $mediaid = $opts{mediaid} + 0;
    confess 'Need a mediaid key'
        unless $mediaid;


    # we need a mogilefs client or we can't edit media
    my $mog = LJ::mogclient()
        or croak 'Sorry, MogileFS is not currently available.';

    my $obj = DW::Media->new( user => $opts{user}, mediaid => $id );

    # FIXME: Better error handling
    die "No such media object" unless $obj->id;

    $opts{user}->do( "UPDATE media SET state='D' WHERE userid=? AND mediaid=?", undef, $opts->{user}->id, $obj->id );
    LJ::mogclient()->delete( $obj->mogkey );

    return 1;
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
