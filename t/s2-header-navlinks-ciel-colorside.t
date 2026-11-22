# t/s2-header-navlinks-ciel-colorside.t
#
# Test S2 header navigation in Ciel and ColorSide.
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

sub load_style_layer {
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

sub stylesheet {
    my (@layers) = @_;
    my $context  = S2::make_context(@layers);
    my $css      = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $context, 'print_stylesheet()' );
    return $css;
}

sub rule {
    my ( $css, $selector ) = @_;
    return join ';', $css =~ /(?:^|[{}])\s*\Q$selector\E\s*\{([^}]*)/g;
}

sub luminance {
    my ($hex) = @_;
    $hex =~ s/\A#//;
    $hex =~ s/(.)/$1$1/g if length $hex == 3;
    my @rgb = map { hex($_) / 255 } $hex =~ /(..)/g;
    @rgb = map { $_ <= 0.04045 ? $_ / 12.92 : ( ( $_ + 0.055 ) / 1.055 )**2.4 } @rgb;
    return 0.2126 * $rgb[0] + 0.7152 * $rgb[1] + 0.0722 * $rgb[2];
}

my $core   = read_style('core2.s2');
my $parent = read_style('core2base/layout.s2');
my $module = '#header .module-navlinks';

for my $layout (qw(ciel colorside)) {
    my $compiler = S2::Compiler->new( {} );
    S2::set_domain("test-header-navlinks-$layout");
    load_style_layer( $compiler, 1, 'core',   $core );
    load_style_layer( $compiler, 2, 'layout', $parent . read_style("$layout/layout.s2") );
    load_style_layer( $compiler, 3, 'user',
        'layerinfo type = "user"; set module_navlinks_section = "header";' );
    load_style_layer( $compiler, 4, 'user',
        'layerinfo type = "user"; set module_navlinks_section = "one";' );
    load_style_layer( $compiler, 5, 'user', <<'S2' );
layerinfo type = "user";
set module_navlinks_section = "header";
set color_header_background = "#123";
set color_page_background = "#fafafa";
set color_page_title = "#fed";
set color_page_text = "#1a1a1a";
S2

    my $header = stylesheet( 1, 2, 5 );
    my $list   = rule( $header, "$module ul" );
    like( $list, qr/\bdisplay:\s*flex\s*;/,   "$layout: header links run horizontally" );
    like( $list, qr/\bflex-wrap:\s*wrap\s*;/, "$layout: header links wrap" );
    like( $list, qr/\bmargin:\s*0\s*;/,       "$layout: no inherited list margin" );
    like( $list, qr/\bpadding:\s*0\s*;/,      "$layout: no inherited list padding" );
    like( rule( $header, "$module li" ),
        qr/\bmargin:\s*0\s*;/, "$layout: no inherited item margin" );
    my $box = rule( $header, $module );
    like( $box, qr/\bbackground:\s*transparent\s*;/, "$layout: module shows the header surface" );
    like( $box, qr/\bborder:\s*none\s*;/,    "$layout: module has no inherited box border" );
    like( $box, qr/\bcolor:\s*#ffeedd\s*;/i, "$layout: legible header title color wins" );

    if ( $layout eq 'ciel' ) {
        like( $box, qr/\bwidth:\s*auto\s*;/, 'ciel: header nav can use more than sidebar width' );
    }
    like( rule( $header, "$module a" ),
        qr/\bcolor:\s*inherit\s*;/, "$layout: links use the header navigation foreground" );

    my $sidebar = stylesheet( 1, 2, 4 );
    unlike( $sidebar, qr/\Q$module\E/, "$layout: no header navigation overrides in sidebar mode" );
    is(
        rule( $header,  '.module-navlinks a' ),
        rule( $sidebar, '.module-navlinks a' ),
        "$layout: original module-specific link styling is unchanged"
    );

    my $themes       = read_style("$layout/themes.s2");
    my @theme_layers = $themes =~ /^#NEWLAYER: (\S+)\n(.*?)(?=^#NEWLAYER:|\z)/msg;
    my ( @low_contrast, @empty_colors, @unbacked_textures );
    my $id = 6;
    while (@theme_layers) {
        my ( $theme, $source ) = splice @theme_layers, 0, 2;
        load_style_layer( $compiler, $id, 'theme', $source );
        my $css  = stylesheet( 1, 2, $id, 3 );
        my $link = rule( $css, "$module a" );
        my ($foreground)      = rule( $css, $module ) =~ /(?:^|[;\s])color:\s*(#[\da-f]{3,6})\s*;/i;
        my ($link_background) = $link =~ /\bbackground-color:\s*(#[\da-f]{3,6})\s*;/i;
        my $context = S2::make_context( 1, 2, $id, 3 );
        my $header_color = S2::get_property_value( $context, 'color_header_background' ) || {};
        my $page_color   = S2::get_property_value( $context, 'color_page_background' )   || {};
        my $background =
            $link_background || $header_color->{as_string} || $page_color->{as_string} || '#fff';
        push @unbacked_textures, $theme
            if $layout eq 'ciel'
            && !$header_color->{as_string}
            && !$link_background
            && S2::get_property_value( $context, 'image_background_page_url' );
        my @levels = sort { $a <=> $b } map { luminance($_) + 0.05 } ( $foreground, $background )
            if $foreground;
        push @low_contrast, $theme unless @levels && $levels[1] / $levels[0] >= 4.5;
        my $nav_css = join ';', map { rule( $css, $_ ) } ( $module, "$module ul", "$module a" );
        push @empty_colors, $theme if $nav_css =~ /(?:color|background):\s*;|\bsolid\s*;/i;
        ++$id;
    }
    cmp_ok( $id, '>', 6, "$layout: built-in themes loaded" );
    ok( !@low_contrast, "$layout: header links have 4.5:1 contrast in every built-in palette" )
        or diag join ', ', @low_contrast;
    is_deeply( \@empty_colors, [], "$layout: unset palette colors don't generate empty CSS" );
    if ( $layout eq 'ciel' ) {
        is_deeply( \@unbacked_textures, [], 'ciel: links have a solid surface over page textures' );
    }
}

done_testing;
