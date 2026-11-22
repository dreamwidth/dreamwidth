# t/s2-header-navlinks-forthebold-funkycircles.t
#
# Test header navigation in For The Bold and Funky Circles.
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
    my ($path) = @_;
    open my $file, '<', "$ENV{LJHOME}/styles/$path" or die "Cannot open $path: $!";
    local $/;
    return <$file>;
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

sub render_stylesheets {
    my (@layers) = @_;
    my $context  = S2::make_context(@layers);
    my $css      = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $context, 'print_stylesheet()' );
    return $css;
}

sub declarations {
    my ( $css, $selector ) = @_;
    $css =~ s{/\*.*?\*/}{}gs;
    my %properties;
    while ( $css =~ /^\s*([^{}]+)\{([^{}]*)\}/mg ) {
        my ( $selectors, $block ) = ( $1, $2 );
        next unless grep { $_ eq $selector } split /\s*,\s*/, $selectors =~ s/\s+$//r;
        while ( $block =~ /([\w-]+):\s*([^;]*?)\s*;/g ) {
            $properties{$1} = $2;
        }
    }
    return \%properties;
}

sub surface_color {
    my ($rule) = @_;
    return $rule->{'background-color'} // ( ( $rule->{background} // '' ) =~ /^(#[0-9a-f]+)/i )[0];
}

sub luminance {
    my ($color) = @_;
    $color = '#fff' if ( $color // '' ) eq 'Canvas';
    $color = '#000' if ( $color // '' ) eq 'CanvasText';
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
for my $layout (qw(forthebold funkycircles)) {
    S2::set_domain("test-header-navlinks-$layout");
    my $compiler = S2::Compiler->new( {} );
    load_layer( $compiler, 1, 'core', read_style('core2.s2') );
    load_layer( $compiler, 2, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );
    my $options = 'layerinfo type = "user"; set custom_control_strip_colors = "off";';
    load_layer( $compiler, 3, 'user', $options . 'set module_navlinks_section = "header";' );
    load_layer( $compiler, 4, 'user', $options . 'set module_navlinks_section = "one";' );

    my $css  = render_stylesheets( 1, 2, 3 );
    my $box  = declarations( $css, $nav );
    my $list = declarations( $css, "$nav .module-list" );
    is( $box->{background}, 'transparent', "$layout: no sidebar module background in the header" );
    is( $box->{border},     'none',        "$layout: no sidebar module border in the header" );
    if ( $layout eq 'funkycircles' ) {
        is( $box->{display}, 'block', 'Funky Circles: header nav is not an inline sidebar box' );
        is( $box->{width},   'auto',  'Funky Circles: header nav is not limited to sidebar width' );
    }
    is( $list->{display},     'flex', "$layout: navigation forms a row" );
    is( $list->{'flex-wrap'}, 'wrap', "$layout: navigation can wrap in narrow headers" );
    is( $list->{margin},      '0',    "$layout: list has no inherited indentation" );
    is( declarations( $css, "$nav .module-content li" )->{margin},
        '0', "$layout: navigation items have no inherited module margins" );
    is( declarations( $css, "$nav a" )->{color}, 'inherit', "$layout: links use the nav color" );

    my $sidebar = render_stylesheets( 1, 2, 4 );
    unlike( $sidebar, qr/\Q$nav\E/,
        "$layout: header rules are not emitted for sidebar navigation" );
    unlike(
        $sidebar,
        qr/\.module-navlinks li\s*\{[^}]*display:\s*inline-block/,
        "$layout: inherited horizontal navigation is not emitted for the sidebar"
    );

    my $themes = read_style("$layout/themes.s2");
    my $id     = 4;
    my @unreadable;
    while ( $themes =~ /^#NEWLAYER: \Q$layout\E\/(\S+)\n(.*?)(?=^#NEWLAYER:|\z)/msg ) {
        my ( $name, $source ) = ( $1, $2 );
        load_layer( $compiler, ++$id, 'theme', $source );
        my $themed     = render_stylesheets( 1, 2, $id, 3 );
        my $foreground = declarations( $themed, $nav )->{color};
        my $background = surface_color( declarations( $themed, "$nav a" ) )
            // surface_color( declarations( $themed, '#header > .inner' ) )
            // surface_color( declarations( $themed, '#header' ) )
            // surface_color( declarations( $themed, 'body' ) );
        my @values =
            sort { $a <=> $b } grep { defined } map { luminance($_) } ( $foreground, $background );
        push @unreadable, $name
            if @values != 2 || ( $values[1] + .05 ) / ( $values[0] + .05 ) < 4.5;
    }
    cmp_ok( $id, '>', 4, "$layout: built-in themes loaded" );
    is_deeply( \@unreadable, [], "$layout: all built-in themes reach 4.5:1 link contrast" );

    is( $box->{color}, 'CanvasText', "$layout: missing palette uses the browser foreground" );
    unlike(
        $css,
        qr/\Q$nav\E[^{}]*\{[^}]*(?:\bcolor:\s*;|\bsolid\s+;)/,
        "$layout: missing colors do not generate empty declarations"
    );
}

done_testing;
