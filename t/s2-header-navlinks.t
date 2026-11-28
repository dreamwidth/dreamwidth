# t/s2-header-navlinks.t
#
# Test the header navigation stylesheet in Brittle and Tranquility III.
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
use S2;
use S2::Compiler;

sub read_style {
    my ($file) = @_;
    open my $source, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$source>;
}

sub load_layer {
    my ( $compiler, $id, $type, $source ) = @_;
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
    S2::load_layer( $id, $compiled, 0 );
}

sub render_css {
    my ($ctx) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    my $page = { _type => 'Page' };
    S2::run_code( $ctx, 'Page::print_default_stylesheet()', $page );
    S2::run_code( $ctx, 'print_stylesheet()' );
    return $css;
}

my $header_nav  = qr/\#header\s+\.module-navlinks/;
my $header_list = qr/$header_nav\s+(?:ul)?\.module-list/;

for my $layout ( 'brittle', 'tranquilityiii' ) {
    S2::set_domain("test-header-navlinks-$layout");
    my $compiler = S2::Compiler->new( {} );
    my $source   = read_style("$layout/layout.s2");
    my @themes;
    if ( $layout eq 'tranquilityiii' ) {
        $source = read_style('core2base/layout.s2') . $source;
        my $theme_source = read_style('tranquilityiii/themes.s2');
        for my $theme ( 'nnwm2009', 'seadeep' ) {
            my ($layer) = $theme_source =~
                /^\#NEWLAYER: tranquilityiii\/\Q$theme\E\n(.*?)(?=^\#NEWLAYER:|\z)/ms;
            BAIL_OUT("Missing theme $theme") unless defined $layer;
            push @themes, $layer;
        }
    }
    load_layer( $compiler, 1, 'core',   read_style('core2.s2') );
    load_layer( $compiler, 2, 'layout', $source );
    load_layer( $compiler, 5, 'theme',  $themes[0] ) if @themes;

    for my $placement ( [ 'header', 3 ], [ 'one', 4 ] ) {
        my ( $section, $layer ) = @$placement;
        load_layer( $compiler, $layer, 'user',
            qq{layerinfo type = "user"; set module_navlinks_section = "$section";} );
        my $ctx = S2::make_context( 1, 2, ( @themes ? (5) : () ), $layer );
        S2::run_code( $ctx, 'prop_init()' );
        S2::run_code( $ctx, 'modules_init()' );
        my $sections       = S2::get_property_value( $ctx, 'module_sections' );
        my $navlinks_order = S2::get_property_value( $ctx, 'module_navlinks_order' );
        is_deeply( $sections->{$section}[$navlinks_order],
            ['navlinks'], "$layout: navigation stays in the selected $section section" );
        my $css = render_css($ctx);

        if ( $section eq 'header' ) {
            my ($declarations) = $css =~ /$header_list\s*\{([^}]*)\}/;
            like(
                $declarations // '',
                qr/display:\s*flex;[^}]*flex-wrap:\s*wrap;/,
                "$layout: header navigation can wrap at narrow widths"
            );
            if (@themes) {
                my ($module) = $css =~ /$header_nav\s*\{([^}]*)\}/;
                like(
                    $module // '',
                    qr/background:\s*transparent;/,
                    'Tranquility III: header navigation shows the header background'
                );
                like(
                    $module // '',
                    qr/border:\s*none;[^}]*border-bottom:/,
                    'Tranquility III: only the divider remains around header navigation'
                );
                like(
                    $css,
                    qr/$header_list\s+li\s*\{[^}]*margin:\s*0;/,
                    'Tranquility III: header list items do not add sidebar spacing'
                );
                like( $module // '',
                    qr/color:\s*\#ef8229;/i,
                    'NNWM 2009: header navigation uses the title color, not the page text color' );
            }
        }
        else {
            unlike( $css, $header_nav, "$layout: sidebar mode omits header navigation rules" );
            if (@themes) {
                like(
                    $css,
                    qr/\.module-content\s+li\s*\{[^}]*margin:\s*\.5em 0;/,
                    'Tranquility III: sidebar retains the base layout list spacing'
                );
            }
        }
    }

    if (@themes) {
        load_layer( $compiler, 6, 'theme', $themes[1] );
        my $ctx = S2::make_context( 1, 2, 6, 3 );
        S2::run_code( $ctx, 'prop_init()' );
        S2::run_code( $ctx, 'modules_init()' );
        my $css = render_css($ctx);
        my ($module) = $css =~ /$header_nav\s*\{([^}]*)\}/;
        like( $module // '',
            qr/color:\s*\#0b0f0c;/i,
            'Sea Deep: header navigation falls back to the page text color' );
        like(
            $module // '',
            qr/border-bottom:\s*1px\s+solid\s+currentColor;/i,
            'Sea Deep: the divider has a valid color without a title color'
        );
    }
}

done_testing;
