#!/usr/bin/perl
#
# DW::Task::DeleteEntry
#
# Worker for asynchronous entry deletion.
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

package DW::Task::DeleteEntry;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::Entry;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $args = $self->args->[0];

    die "Failed to delete entry.\n"
        unless LJ::delete_entry(
        $args->{uid},
        $args->{jitemid},
        0,              # not quick, do it all
        $args->{anum},
        );

    return DW::Task::COMPLETED;
}

1;
