#!/usr/bin/perl
#
# DW::Task::ESN::ProcessSub
#
# ESN worker to do final subscription processing.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::Test;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use base 'DW::Task';

sub work {
    my $self = $_[0];
    my $a    = $self->args;

    print "Starting work...\n";
    use Data::Dumper qw/ Dumper /;
    print Dumper($a);

    return DW::Task::COMPLETED;
}

1;

