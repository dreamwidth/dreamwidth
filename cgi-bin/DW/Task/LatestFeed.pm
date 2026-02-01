#!/usr/bin/perl
#
# DW::Task::LatestFeed
#
# Worker to process latest feed items.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::LatestFeed;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::LatestFeed;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $opts = $self->args->[0];
    DW::LatestFeed->_process_item($opts);

    return DW::Task::COMPLETED;
}

1;
