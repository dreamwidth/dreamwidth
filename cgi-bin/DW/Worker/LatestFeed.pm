#!/usr/bin/perl
#
# DW::Worker::LatestFeed
#
# Intermediary worker that lets us pipeline new items so we only have one
# task that can process them at a time.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::LatestFeed;

use strict;
use base 'TheSchwartz::Worker';
use DW::LatestFeed;

sub work {
    my ( $class, $job ) = @_;
    my $opts = $job->arg;

    # FIXME: we might want to lock here, to protect against the sysadmin running
    # more than one copy of this job?  otoh, we should just document that there
    # should only ever be one of these running.

    # all we do is pass this back to the proper module, this keeps the logic in
    # one place so we don't have to track it down through four files :)
    DW::LatestFeed->_process_item($opts);

    $job->completed;
}

1;
