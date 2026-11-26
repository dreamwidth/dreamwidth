# t/s2-header-navlinks-snakesandboxes-steppingstones.t
#
# Test the generated header navigation CSS for Snakes & Boxes and Stepping Stones.
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

my $compiler = S2::Compiler->new( {} );
my $next_id  = 0;
S2::set_domain('test-snakesandboxes-steppingstones-navlinks');

sub load_layer {
    my ( $type, $source ) = @_;
    my $id = ++$next_id;
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
    return $id;
}

sub stylesheets {
    my (@layers) = @_;
    my $context  = S2::make_context(@layers);
    my $css      = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $context, 'print_stylesheet()' );
    return $css;
}

sub declaration {
    my ( $css, $selector, $property ) = @_;
    my @rules  = $css =~ /(?:^|[},\n])\s*\Q$selector\E\s*\{([^{}]*)\}/g;
    my @values = join( ';', @rules ) =~ /(?:^|;)\s*\Q$property\E\s*:\s*([^;]*?)\s*;/g;
    return $values[-1];
}

sub header_options {
    my ($settings) = @_;
    return load_layer( 'user',
        'layerinfo type = "user"; set module_navlinks_section = "header"; ' . $settings );
}

sub luminance {
    my ($color) = @_;
    $color =~ s/\A#([a-f0-9])([a-f0-9])([a-f0-9])\z/#$1$1$2$2$3$3/i;
    my @channels = $color =~ /\A#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})\z/i;
    return unless @channels;
    my ( $red, $green, $blue ) = map {
        my $value = hex($_) / 255;
        $value <= 0.04045 ? $value / 12.92 : ( ( $value + 0.055 ) / 1.055 )**2.4;
    } @channels;
    return 0.2126 * $red + 0.7152 * $green + 0.0722 * $blue;
}

my $nav  = '#header .module-navlinks';
my $core = load_layer( 'core', read_style('core2.s2') );
my $base = read_style('core2base/layout.s2');

for my $name (qw(snakesandboxes steppingstones)) {
    my $layout = load_layer( 'layout', $base . read_style("$name/layout.s2") );
    my $header = header_options('');
    my $sidebar =
        load_layer( 'user', 'layerinfo type = "user"; set module_navlinks_section = "one";' );

    my $css = stylesheets( $core, $layout, $header );
    is( declaration( $css, $nav, 'background' ), 'transparent', "$name: no sidebar fill" );
    is( declaration( $css, $nav, 'border' ),     'none',        "$name: no sidebar border" );
    is( declaration( $css, "$nav .module-content li", 'margin' ),
        '0', "$name: no sidebar item margins" );
    is( declaration( $css, "$nav .module-list", 'flex-wrap' ), 'wrap', "$name: navigation wraps" );
    is( declaration( $css, "$nav a", 'color' ),
        'inherit', "$name: links use header navigation color" );
    unlike( $css, qr/\Q$nav\E[^{}]*\{[^{}]*:\s*;/, "$name: no empty navigation declarations" );
    unlike( stylesheets( $core, $layout, $sidebar ),
        qr/\Q$nav\E/, "$name: sidebar CSS is unchanged" );

    my $transparent_header = header_options('set color_header_background = "";');
    my $pale_page          = load_layer( 'theme', <<'S2' );
layerinfo type = "theme";
set color_page_background = "#f2f5ec";
set color_page_title = "#123456";
S2
    is(
        declaration(
            stylesheets( $core, $layout, $pale_page, $transparent_header ), $nav, 'color'
        ),
        '#123456',
        "$name: transparent header uses the page background for contrast"
    );

    my $empty_colors = header_options(<<'S2');
set color_header_background = "";
set color_page_background = "";
set color_page_title = "#ffffff";
S2
    is( declaration( stylesheets( $core, $layout, $empty_colors ), $nav, 'color' ),
        'inherit', "$name: no background color inherits the foreground" );

    my $empty_title = header_options(<<'S2');
set color_header_background = "#f2f5ec";
set color_page_title = "";
set color_page_text = "#123456";
S2
    is( declaration( stylesheets( $core, $layout, $empty_title ), $nav, 'color' ),
        '#123456', "$name: empty title color falls through to the page text color" );

    my $empty_foreground = header_options(<<'S2');
set color_header_background = "#f2f5ec";
set color_page_title = "";
set color_page_text = "";
S2
    is( declaration( stylesheets( $core, $layout, $empty_foreground ), $nav, 'color' ),
        '#000000', "$name: empty foreground candidates fall back to a contrasting swatch" );

    my $themes = read_style("$name/themes.s2");
    while ( $themes =~ /^\#NEWLAYER: ([^\n]+)\n(.*?)(?=^\#NEWLAYER:|\z)/msg ) {
        my ( $theme_name, $source ) = ( $1, $2 );
        my $theme      = load_layer( 'theme', $source );
        my $themed_css = stylesheets( $core, $layout, $theme, $header );
        my $background = luminance(
            declaration( $themed_css, '#header > .inner:first-child', 'background-color' )
                // declaration( $themed_css, '#header', 'background' ) // '' );
        $background //= luminance( declaration( $themed_css, 'body', 'background-color' ) // '' );
        my $foreground = luminance( declaration( $themed_css, $nav, 'color' ) // '' );
        my @levels     = sort { $a <=> $b } ( $foreground // 0, $background // 0 );
        my $ratio =
            defined $background && defined $foreground
            ? ( $levels[1] + 0.05 ) / ( $levels[0] + 0.05 )
            : 0;
        cmp_ok( $ratio, '>=', 4.5,
            "$theme_name: readable header navigation against the theme background" );

        if ( $theme_name eq 'steppingstones/icechic' ) {
            my $overridden_css = stylesheets( $core, $layout, $theme, $transparent_header );
            is( declaration( $overridden_css, $nav, 'color' ),
                '#060606', 'Ice Chic: transparent header keeps dark navigation text' );
        }
    }
}

done_testing;
