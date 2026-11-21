# t/s2-site-logos.t
#
# Test that S2 layouts can read configured site logo URLs.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use S2::Checker;
use S2::Compiler;

open my $core_file, '<', "$ENV{LJHOME}/styles/core2.s2" or die "Open core2.s2: $!";
my $core_source = do { local $/; <$core_file> };
close $core_file;

my $layout_source = <<'S2';
layerinfo "type" = "layout";
function test_logo() : string { return $*SITELOGO; }
function test_logo_icon() : string { return $*SITELOGOICON; }
S2

my $compiler = S2::Compiler->new( { checker => S2::Checker->new } );
foreach my $layer ( [ 1, 'core', $core_source ], [ 2, 'layout', $layout_source ] ) {
    my ( $id, $type, $source ) = @$layer;
    my $compiled;
    $compiler->compile_source(
        {
            type           => $type,
            source         => \$source,
            output         => \$compiled,
            layerid        => $id,
            builtinPackage => 'S2::Builtin::LJ',
        }
    );
    eval $compiled;
    die $@ if $@;
}

local $LJ::IMGPREFIX = 'https://static.example/img';
local $LJ::SITE_LOGO_IMAGE;
local $LJ::SITE_LOGO_ICON_IMAGE;
check_logos( '', '', 'unconfigured site' );

$LJ::SITE_LOGO_ICON_IMAGE = 'logo-icon.png';
check_logos( '', 'https://static.example/img/logo-icon.png', 'icon only' );

$LJ::IMGPREFIX            = '/img';
$LJ::SITE_LOGO_IMAGE      = 'branding/logo.png';
$LJ::SITE_LOGO_ICON_IMAGE = '';
check_logos( '/img/branding/logo.png', '', 'full logo only with a relative image prefix' );

done_testing;

sub check_logos {
    my ( $logo, $icon, $label ) = @_;
    my $context = S2::make_context( [ 1, 2 ] );
    LJ::S2::populate_system_props($context);
    is( S2::run_function( $context, 'test_logo()' ),      $logo, "$label: full logo" );
    is( S2::run_function( $context, 'test_logo_icon()' ), $icon, "$label: logo icon" );
}
