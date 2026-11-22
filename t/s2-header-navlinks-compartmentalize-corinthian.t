# t/s2-header-navlinks-compartmentalize-corinthian.t
#
# Test header navigation in Compartmentalize and Corinthian.
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

sub render_stylesheets {
    my (@layers) = @_;
    my $ctx      = S2::make_context(@layers);
    my $css      = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $ctx, 'print_stylesheet()' );
    S2::run_code( $ctx, 'Page::print_theme_stylesheet()', { _type => 'Page' } );
    return $css;
}

sub declarations {
    my ( $css, $selector ) = @_;
    my %properties;
    while ( $css =~ /^\s*\Q$selector\E\s*\{([^{}]*)\}/mg ) {
        my $block = $1;
        while ( $block =~ /([\w-]+):\s*([^;]*?)\s*;/g ) {
            $properties{$1} = $2;
        }
    }
    return \%properties;
}

sub luminance {
    my ($color) = @_;
    return unless defined $color && $color =~ /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;
    my $hex = $1;
    $hex =~ s/(.)/$1$1/g if length($hex) == 3;
    my ( $red, $green, $blue ) = map {
        my $channel = hex($_) / 255;
        $channel <= 0.04045 ? $channel / 12.92 : ( ( $channel + 0.055 ) / 1.055 )**2.4;
    } $hex =~ /(..)/g;
    return 0.2126 * $red + 0.7152 * $green + 0.0722 * $blue;
}

my $nav = '#header .module-navlinks';
for my $layout (qw(compartmentalize corinthian)) {
    S2::set_domain("test-header-navlinks-$layout");
    my $compiler = S2::Compiler->new( {} );
    load_style_layer( $compiler, 1, 'core', read_style('core2.s2') );
    load_style_layer( $compiler, 2, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );
    load_style_layer( $compiler, 3, 'user',
        'layerinfo type = "user"; set module_navlinks_section = "header";' );
    load_style_layer( $compiler, 4, 'user',
        'layerinfo type = "user"; set module_navlinks_section = "one";' );

    my $themes = read_style("$layout/themes.s2");
    my $id     = 4;
    my ( @low_contrast, %theme_id );
    while ( $themes =~ /^#NEWLAYER: \Q$layout\E\/(\S+)\n(.*?)(?=^#NEWLAYER:|\z)/msg ) {
        my ( $name, $source ) = ( $1, $2 );
        $theme_id{$name} = ++$id;
        load_style_layer( $compiler, $id, 'theme', $source );
        my $css          = render_stylesheets( 1, 2, $id, 3 );
        my $foreground   = declarations( $css, $nav )->{color};
        my $header       = declarations( $css, '#header' );
        my ($background) = ( $header->{'background-color'} // $header->{background} ) =~ /^(#\w+)/;
        my @luminances   = map { luminance($_) } ( $foreground, $background );
        my ( $darker, $lighter ) = sort { $a <=> $b } @luminances;
        push @low_contrast, $name
            if @luminances != 2 || ( $lighter + .05 ) / ( $darker + .05 ) < 4.5;
    }
    is_deeply( \@low_contrast, [], "$layout: links have 4.5:1 contrast in every built-in theme" );

    my $sample  = $theme_id{icechic} or BAIL_OUT("$layout Ice Chic is missing");
    my $header  = render_stylesheets( 1, 2, $sample, 3 );
    my $sidebar = render_stylesheets( 1, 2, $sample, 4 );
    my $panel   = declarations( $header, $nav );
    is( $panel->{background}, 'transparent', "$layout: header nav has no module background" );
    is( $panel->{border},     'none',        "$layout: header nav has no module border" );
    is(
        $panel->{color},
        declarations( $header, '#header' )->{color},
        "$layout: header nav keeps a readable theme title color"
    );
    is( declarations( $header, "$nav a" )->{color},
        'inherit', "$layout: links use the header nav foreground" );
    my $list = declarations( $header, "$nav .module-list" );
    is( $list->{display},     'flex', "$layout: nav links form a horizontal list" );
    is( $list->{'flex-wrap'}, 'wrap', "$layout: nav links can wrap in narrow headers" );
    is( $list->{margin},      '0',    "$layout: nav list clears inherited margin" );
    is( $list->{padding},     '0',    "$layout: nav list clears inherited padding" );
    is( declarations( $header, "$nav .module-list li" )->{margin},
        '0', "$layout: list items clear inherited margin" );
    unlike( $sidebar, qr/\Q$nav\E/, "$layout: header nav rules are not emitted in sidebar mode" );
    unlike(
        $sidebar,
        qr/\.module-navlinks li\s*\{[^}]*display:\s*inline-block/,
        "$layout: inherited horizontal nav is not emitted in sidebar mode"
    );

    load_style_layer( $compiler, ++$id, 'user', <<'S2' );
layerinfo type = "user";
set module_navlinks_section = "header";
set color_page_title = "";
set color_page_text = "";
set color_header_background = "";
set color_page_background = "";
set color_entry_background = "";
S2
    my $unset = render_stylesheets( 1, 2, $sample, $id );
    is( declarations( $unset, $nav )->{color},
        'CanvasText', "$layout: uncolored headers use the browser's canvas foreground" );
    unlike(
        $unset,
        qr/\Q$nav\E[^{}]*\{[^}]*(?:\bcolor:\s*;|\bsolid\s+;)/,
        "$layout: unset colors do not emit empty nav declarations"
    );
}

done_testing;
