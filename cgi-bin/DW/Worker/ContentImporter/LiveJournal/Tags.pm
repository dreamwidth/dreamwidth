#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Tags
#
# Importer worker for LiveJournal-based sites tags.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::LiveJournal::Tags;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use DW::Worker::ContentImporter::Local::Tags;

sub run {
    my ( $class, $ctx ) = @_;
    my ( $u, $data ) = ( $ctx->u, $ctx->data );

    # get tags
    my $r           = $class->call_xmlrpc( $data, 'getusertags' );
    my $xmlrpc_fail = 'XMLRPC failure: ' . ( $r ? $r->{faultString} : '[unknown]' );
    $xmlrpc_fail .= " (community: $data->{usejournal})" if $data->{usejournal};
    return $ctx->temp_fail($xmlrpc_fail) if !$r || $r->{fault};

    DW::Worker::ContentImporter::Local::Tags->merge_tags( $u, $r->{tags} );

    return $ctx->ok;
}

1;
