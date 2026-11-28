# t/s2-header-navlinks-drifting-goldleaf.t
#
# Test the header navigation stylesheet in Drifting and Gold Leaf.
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
    S2::run_code( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $ctx, 'print_stylesheet()' );
    S2::run_code( $ctx, 'Page::print_theme_stylesheet()', { _type => 'Page' } );
    return $css;
}

sub declarations {
    my ( $css, $selector ) = @_;
    return join '', $css =~ /(?:^|\})\s*\Q$selector\E\s*\{([^}]*)\}/gm;
}

sub luminance {
    my ($hex) = @_;
    $hex =~ s/^#//;
    $hex =~ s/(.)/$1$1/g if length($hex) == 3;
    my ( $red, $green, $blue ) = map {
        my $channel = hex($_) / 255;
        $channel <= 0.04045 ? $channel / 12.92 : ( ( $channel + 0.055 ) / 1.055 )**2.4;
    } $hex =~ /(..)/g;
    return 0.2126 * $red + 0.7152 * $green + 0.0722 * $blue;
}

my $nav    = '#header .module-navlinks';
my $header = '#canvas #header';
my $hex    = qr/\#[0-9a-fA-F]{6}\b|\#[0-9a-fA-F]{3}\b/;

for my $layout (qw(drifting goldleaf)) {
    S2::set_domain("test-header-navlinks-$layout");
    my $compiler = S2::Compiler->new( {} );
    load_layer( $compiler, 1, 'core',   read_style('core2.s2') );
    load_layer( $compiler, 2, 'layout', read_style("$layout/layout.s2") );
    my $user_style = 'layerinfo type = "user"; set custom_control_strip_colors = "off";';
    load_layer( $compiler, 3, 'user', qq{$user_style set module_navlinks_section = "header";} );
    load_layer( $compiler, 4, 'user', qq{$user_style set module_navlinks_section = "one";} );
    my @themes   = ( [ 'default', [] ] );
    my $theme_id = 10;

    for my $source ( grep { /layerinfo/ } split /^#NEWLAYER: /m, read_style("$layout/themes.s2") ) {
        my ($name) = $source =~ /layerinfo name = "([^"]+)"/;
        $source =~ s/^[^\n]*\n//;
        load_layer( $compiler, $theme_id, 'theme', $source );
        push @themes, [ $name, [ $theme_id++ ] ];
    }

    for my $theme (@themes) {
        my ( $name, $layers ) = @$theme;
        my $ctx = S2::make_context( 1, 2, @$layers, 3 );
        S2::run_code( $ctx, 'prop_init()' );
        S2::run_code( $ctx, 'modules_init()' );
        my $sections = S2::get_property_value( $ctx, 'module_sections' );
        my $order    = S2::get_property_value( $ctx, 'module_navlinks_order' );
        is_deeply( $sections->{header}[$order],
            ['navlinks'], "$layout/$name: navigation can be assigned to the header" );

        my $css = render_css($ctx);
        if ( $layout eq 'drifting' && $name eq 'Soft Blues' ) {
            like( declarations( $css, "#header,\n    .header-right" ),
                qr/height:\s*5\.813em;/, 'Soft Blues renders its theme-specific header height' );
            like( declarations( $css, $header ),
                qr/height:\s*auto;/, 'Soft Blues: the header can grow to contain navigation' );
            my $theme_sidebar = S2::make_context( 1, 2, @$layers, 4 );
            is( declarations( render_css($theme_sidebar), $header ),
                '', 'Soft Blues: sidebar mode keeps the theme-specific header height' );
        }
        my $box  = declarations( $css, $nav );
        my $list = declarations( $css, "$nav .module-list" );
        my $link = declarations( $css, "$nav a" );
        like( $box,  qr/background:\s*transparent;/, "$layout/$name: no sidebar background" );
        like( $box,  qr/border:\s*none;/,            "$layout/$name: no sidebar border" );
        like( $list, qr/display:\s*flex;/,           "$layout/$name: links are horizontal" );
        like( $list, qr/flex-wrap:\s*wrap;/,         "$layout/$name: links can wrap" );
        like( $list, qr/margin:\s*0;/,               "$layout/$name: no inherited list margin" );
        like( $list, qr/padding:\s*0;/,              "$layout/$name: no inherited list padding" );
        like( $link, qr/color:\s*inherit;/, "$layout/$name: links use the header nav foreground" );
        unlike( "$box$list$link", qr/:\s*;|\bsolid\s*;/, "$layout/$name: no empty CSS colors" );

        my ($foreground) = $box =~ /\bcolor:\s*($hex)\s*;/;
        my ($background) =
            join( '', map { declarations( $css, $_ ) } '#header', '#canvas', 'body' ) =~
            /\bbackground(?:-color)?:\s*($hex)/;
        my @lightness = sort { $a <=> $b } map { luminance($_) } $foreground // '#fff',
            $background // '#fff';
        cmp_ok( ( $lightness[1] + 0.05 ) / ( $lightness[0] + 0.05 ),
            '>=', 4.5,
            "$layout/$name: header links have readable contrast against the header color" );
    }

    my $sidebar = S2::make_context( 1, 2, 4 );
    S2::run_code( $sidebar, 'prop_init()' );
    S2::run_code( $sidebar, 'modules_init()' );
    if ( $layout eq 'goldleaf' ) {
        my $overrides = S2::get_property_value( $sidebar, 'grouped_property_override' );
        is(
            $overrides->{module_navlinks_section},
            'module_navlinks_section_override',
            'Gold Leaf: the group override can change navigation placement'
        );
    }
    my $sections = S2::get_property_value( $sidebar, 'module_sections' );
    my $order    = S2::get_property_value( $sidebar, 'module_navlinks_order' );
    is_deeply( $sections->{one}[$order], ['navlinks'], "$layout: sidebar keeps its navigation" );
    unlike( render_css($sidebar), qr/\Q$nav\E/, "$layout: sidebar mode omits header-only rules" );
}

done_testing;
