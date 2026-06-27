#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Autoscaler::Window;

my $now     = 1000;
my @samples = ( [ 940, 0.2 ], [ 970, 0.4 ], [ 990, 0.9 ], [ 1000, 1.0 ] );

# 45s window: only ts >= 955 -> (0.4, 0.9, 1.0) avg = 0.766...
my $w = DW::Autoscaler::Window::average( \@samples, 45, $now );
ok( abs( $w - ( ( 0.4 + 0.9 + 1.0 ) / 3 ) ) < 1e-9, '45s window averages last three' );

# 300s window: all four -> 0.625
is( DW::Autoscaler::Window::average( \@samples, 300, $now ), 0.625, '300s window averages all' );

# undef samples are skipped
my @withundef = ( [ 990, undef ], [ 1000, 0.8 ] );
is( DW::Autoscaler::Window::average( \@withundef, 45, $now ), 0.8, 'undef samples skipped' );

# no samples in window -> undef
is( DW::Autoscaler::Window::average( [ [ 100, 0.5 ] ], 45, $now ), undef, 'empty window => undef' );
