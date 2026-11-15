#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Verify
#
# Importer worker for LiveJournal-based site verification of logins and
# passwords.
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

package DW::Worker::ContentImporter::LiveJournal::Verify;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

sub run {
    my ( $class, $ctx ) = @_;
    my $data = $ctx->data;

    # we verify by doing a simple tags call.  yes, this means that we end up
    # getting a user's tags twice... but I'm okay with that, we'll live
    my $r = $class->call_xmlrpc( $data, 'getusertags' );

    # now, we have to see if the error contains 'Invalid password' or something else
    if ( $r && $r->{fault} && $r->{faultString} =~ /Invalid password/ ) {

        # this is a permanent failure.  if the password is bad, we're not going to ever
        # bother retrying.  that's life. (the rest of the import is aborted with it.)
        return $ctx->fail(
            "Username or password for $data->{username} rejected by $data->{hostname}.");
    }

    # if we got any other type of failure, call it temporary...
    return $ctx->temp_fail( 'XMLRPC failure: ' . $r->{faultString} )
        if !$r || $r->{fault};

    # If this is a community import, we have to do a second step now to make sure
    # that the user is an administrator of the remote community. The best way I can
    # come up with is try to unban the owner -- if it works, you're an admin.
    if ( $data->{usejournal} ) {
        $r = $class->call_xmlrpc(
            $data,
            'consolecommand',
            {
                commands => ["ban_unset $data->{username} from $data->{usejournal}"],
            }
        );

        my $xmlrpc_fail = 'XMLRPC failure: ' . ( $r ? $r->{faultString} : '[unknown]' );
        $xmlrpc_fail .= " (community: $data->{usejournal})";
        return $ctx->temp_fail($xmlrpc_fail) if !$r || $r->{fault};
        return $ctx->fail( 'You are not an administrator/maintainer of the remote'
                . ' community named '
                . $data->{usejournal}
                . '.' )
            unless $r->{results}->[0]->{output}->[0]->[0] eq 'success';
    }

    # the user is not told that this passed (the item doesn't notify on success), it
    # doesn't matter to them unless it fails
    return $ctx->ok;
}

1;
