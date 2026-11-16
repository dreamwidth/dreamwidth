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
    my $source = $class->source_for($ctx);

    # we verify by doing a simple tags call.  yes, this means that we end up
    # getting a user's tags twice... but I'm okay with that, we'll live. a rejected password
    # is a permanent failure (and the rest of the import is aborted with it).
    $source->login_check;

    # If this is a community import, we have to do a second step now to make sure
    # that the user is an administrator of the remote community.
    if ( $ctx->data->{usejournal} ) {

        # this is a command run on the remote site, which a dry run must not do
        if ( $ctx->dry_run ) {
            $ctx->sink->note(
                warning => text => 'Not run in a dry run: checking that you administer the '
                    . "remote community by unbanning yourself in it ($ctx->{data}->{usejournal})" );
        }
        else {
            $source->community_admin_check;
        }
    }

    # the user is not told that this passed (the item doesn't notify on success), it
    # doesn't matter to them unless it fails
    return $ctx->ok;
}

1;
