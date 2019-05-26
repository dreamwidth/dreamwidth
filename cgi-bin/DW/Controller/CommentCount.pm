#!/usr/bin/perl
#
# DW::Controller::CommentCount
#
# Creates an image that shows the current number of comments on
# the given post.
#
# Authors:
#      Allen Petersen
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::CommentCount;

use strict;
use warnings;
use DW::Routing;
use Image::Magick;

DW::Routing->register_string(
    "/tools/commentcount", \&commentcount_handler,
    app    => 1,
    format => 'png'
);

sub commentcount_handler {
    my $r    = DW::Request->get;
    my $args = $r->get_args;

    my $count = $args->{samplecount} || 0;

    my $entry = undef;

    if ( $args->{ditemid} && $args->{user} ) {
        my $ditemid = $args->{ditemid};
        my $uid     = LJ::get_userid( $args->{user} );
        $entry = LJ::Entry->new( $uid, ditemid => $ditemid ) if $uid;
        $entry = undef unless $entry && $entry->valid;
    }

    $count = $entry->reply_count if $entry;

    # create an image
    my $image = Image::Magick->new;
    $image->Set( pen       => 'black' );
    $image->Set( font      => 'Generic.ttf' );
    $image->Set( pointsize => 12 );
    $image->Set( size      => '30x12' );
    $image->Read("label:$count");

    # return the image
    $r->print( $image->ImageToBlob( magick => "png" ) );

    return $r->OK;
}

1;
