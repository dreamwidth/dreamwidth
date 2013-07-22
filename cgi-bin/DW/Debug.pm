#!/usr/bin/perl
#
# DW::Debug
#
# Debug methods
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Debug;
use strict;

use DW::Request;
use Time::HiRes;

sub mark_time {
    my $what = $_[1];

    my $r = DW::Request->get;
    my $time_data = $LJ::REQUEST_CACHE{"time_mark"};

    unless ( $time_data ) {
        $time_data = {
            start => Time::HiRes::time,
            ct    => 0,
        };
    }

    $r->header_out("X-DW-Time",
        sprintf("%i %.6f %s",
            $time_data->{ct}++,
            0, #Time::HiRes::time - $time_data->{start},
            $what ) );

    $LJ::REQUEST_CACHE{"time_mark"} = $time_data;
}

1;
