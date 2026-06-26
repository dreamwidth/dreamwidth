#!/usr/bin/perl
#
# DW::Autoscaler::Window
#
# Pure trailing-window averaging used to smooth occupancy samples so the
# controller reacts to a sustained trend, not a single noisy tick.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.

package DW::Autoscaler::Window;

use strict;
use warnings;

# average(\@samples, $window_secs, $now) -> mean value, or undef if none.
# @samples is an arrayref of [timestamp, value]; value may be undef (skipped).
sub average {
    my ( $samples, $window, $now ) = @_;
    my ( $sum, $count ) = ( 0, 0 );
    foreach my $s (@$samples) {
        next if $s->[0] < $now - $window;
        next unless defined $s->[1];
        $sum += $s->[1];
        $count++;
    }
    return undef unless $count;
    return $sum / $count;
}

1;
