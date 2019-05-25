# t/s2-color.t
#
# Test S2::Builtin::LJ::Color* functions.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 14;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

# As all of these are builtins, fake context.
my $ctx = [];

# Construct from #xxx form

check_rgb( "short color with hash",    make_color("#fed"),    hex("ff"), hex("ee"), hex("dd") );
check_rgb( "short color without hash", make_color("fed"),     hex("ff"), hex("ee"), hex("dd") );
check_rgb( "long color with hash",     make_color("#deadbe"), hex("de"), hex("ad"), hex("be") );
check_rgb( "long color without hash",  make_color("deadbe"),  hex("de"), hex("ad"), hex("be") );

subtest "set hsl" => sub {
    plan tests => 1;
    my $clr = make_color("#000000");
    S2::Builtin::LJ::Color__set_hsl( $ctx, $clr, 85, 255, 128 );
    is( $clr->{as_string}, "#01ff01", "string" );
};

subtest "red setter" => sub {
    plan tests => 3;
    my $clr = make_color("#000000");
    is( S2::Builtin::LJ::Color__red( $ctx, $clr, hex("f0") ), hex("f0"), "setter return" );
    is( S2::Builtin::LJ::Color__red( $ctx, $clr ), hex("f0"), "getter after set" );
    is( $clr->{as_string}, "#f00000", "string" );
};

subtest "green setter" => sub {
    plan tests => 3;
    my $clr = make_color("#000000");
    is( S2::Builtin::LJ::Color__green( $ctx, $clr, hex("f0") ), hex("f0"), "setter return" );
    is( S2::Builtin::LJ::Color__green( $ctx, $clr ), hex("f0"), "getter after set" );
    is( $clr->{as_string}, "#00f000", "string" );
};

subtest "blue setter" => sub {
    plan tests => 3;
    my $clr = make_color("#000000");
    is( S2::Builtin::LJ::Color__blue( $ctx, $clr, hex("f0") ), hex("f0"), "setter return" );
    is( S2::Builtin::LJ::Color__blue( $ctx, $clr ), hex("f0"), "getter after set" );
    is( $clr->{as_string}, "#0000f0", "string" );
};

is( S2::Builtin::LJ::Color__hue( $ctx, make_color("#ffff00") ), 43, "hue getter" );

subtest "hue setter" => sub {
    plan tests => 3;
    my $clr = make_color("#ffff00");
    is( S2::Builtin::LJ::Color__hue( $ctx, $clr, 20 ), 20, "setter return" );
    is( S2::Builtin::LJ::Color__hue( $ctx, $clr ), 20, "getter after set" );
    is( $clr->{as_string}, "#ff7901", "string" );
};

is( S2::Builtin::LJ::Color__saturation( $ctx, make_color("#ffff00") ), 255, "saturation getter" );

subtest "saturation setter" => sub {
    plan tests => 3;
    my $clr = make_color("#00ff00");
    is( S2::Builtin::LJ::Color__saturation( $ctx, $clr, 128 ), 128, "setter return" );
    is( S2::Builtin::LJ::Color__saturation( $ctx, $clr ), 128, "getter after set" );
    is( $clr->{as_string}, "#40c040", "string" );
};

is( S2::Builtin::LJ::Color__lightness( $ctx, make_color("#ffff00") ), 128, "lightness getter" );

subtest "lightness setter" => sub {
    plan tests => 3;
    my $clr = make_color("#141300");
    is( S2::Builtin::LJ::Color__lightness( $ctx, $clr, 128 ), 128, "setter return" );
    is( S2::Builtin::LJ::Color__lightness( $ctx, $clr ), 128, "getter after set" );
    is( $clr->{as_string}, "#fff001", "string" );
};

# FIXME: test clone, lighter, darker, inverse, average, blend

sub make_color {
    return S2::Builtin::LJ::Color__Color(@_);
}

sub check_rgb {
    my ( $why, $clr, $r, $g, $b ) = @_;

    # Telling Test::Builder ( which Test::More uses ) to
    # look one level further up the call stack.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    subtest $why => sub {
        plan tests => 3;

        is( S2::Builtin::LJ::Color__red( $ctx, $clr ), $r, "red component" );
        is( S2::Builtin::LJ::Color__green( $ctx, $clr ), $g, "green component" );
        is( S2::Builtin::LJ::Color__blue( $ctx, $clr ), $b, "blue component" );
    }
}
