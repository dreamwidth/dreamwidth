#!/usr/bin/perl
#
# t/currents.t
#
# Test LJ::currents, which assembles the mood/music/location metadata shown on
# an entry. Regression guard: LJ::currents renders the location through
# LJ::Location, but nothing on the render path used to load that module, so the
# eval-wrapped call died silently and the location vanished from every entry.
# This test deliberately does NOT `use LJ::Location` itself -- it must exercise
# the same dependency the render path relies on.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Entry;

my %current = LJ::currents(
    {
        current_location => "Testville",
        current_music    => "a song",
        current_mood     => "happy",
    },
    undef
);

is( $current{Location}, "Testville",
    "location renders (LJ::Location is loaded on the render path)" );
is( $current{Music}, "a song", "music renders" );
is( $current{Mood},  "happy",  "mood renders" );

# Coordinates-only entries fall back to the numeric location.
my %coords = LJ::currents( { current_coords => "45.2345,-123.1234" }, undef );
is( $coords{Location}, "45.2345,-123.1234", "coords-only location renders" );
