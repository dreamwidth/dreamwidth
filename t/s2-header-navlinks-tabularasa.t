# t/s2-header-navlinks-tabularasa.t
#
# Test Tabula Rasa header navigation and child layout isolation.
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

sub compile_layer {
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
    return $compiled;
}

sub render_stylesheets {
    my ($ctx) = @_;
    return map {
        my $css = '';
        local $S2::pout   = sub { $css .= join '', @_ };
        local $S2::pout_s = $S2::pout;
        S2::run_code( $ctx, $_, { _type => 'Page' } );
        $css;
    } qw(Page::print_default_stylesheet() Page::print_theme_stylesheet());
}

sub declarations {
    my ( $css, $selector ) = @_;
    my %properties;
    while ( $css =~ /^\s*\Q$selector\E\s*\{([^{}]*)\}/mg ) {
        my $block = $1;
        $properties{$1} = $2 while $block =~ /([\w-]+):\s*([^;]*?)\s*;/g;
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

my $core     = read_style('core2.s2');
my $base     = read_style('core2base/layout.s2');
my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-header-navlinks-tabularasa');
S2::load_layer( 1, compile_layer( $compiler, 1, 'core',   $core ), 0 );
S2::load_layer( 2, compile_layer( $compiler, 2, 'layout', $base ), 0 );

my $layerid = 2;
my %user;
for my $section ( 'default', 'header', 'one' ) {
    my $id     = $user{$section} = ++$layerid;
    my $source = qq{layerinfo type = "user"; set custom_control_strip_colors = "off";};
    $source .= qq{set module_navlinks_section = "$section";} unless $section eq 'default';
    S2::load_layer( $id, compile_layer( $compiler, $id, 'user', $source ), 0 );
}

my $themes = read_style('core2base/themes.s2');
my %theme;
while ( $themes =~ /^#NEWLAYER: core2base\/(\S+)\n(.*?)(?=^#NEWLAYER:|\z)/msg ) {
    my ( $name, $source ) = ( $1, $2 );
    my $id = $theme{$name} = ++$layerid;
    S2::load_layer( $id, compile_layer( $compiler, $id, 'theme', $source ), 0 );
}
BAIL_OUT('Missing Tabula Rasa theme fixtures')
    if grep { !exists $theme{$_} } qw(dazzle kelis muted nnwm2009 shanice tabac testing);

my $nav   = '#header .module-navlinks';
my $panel = '#header .module.module-navlinks';
for my $name ( sort keys %theme ) {
    my ( $defaults, $theme_css ) =
        render_stylesheets( S2::make_context( 1, 2, $theme{$name}, $user{header} ) );
    my $color  = declarations( $theme_css, $nav )->{color};
    my $header = declarations( $defaults,  '#header' );
    my $body   = declarations( $defaults,  'body' );
    my $background = luminance( $header->{'background-color'} // $header->{background} );
    $background //= luminance( $body->{'background-color'} // $body->{background} );
    if ( defined $background ) {
        my $foreground = luminance($color);
        if ( !defined $foreground ) {
            fail("$name: header navigation has a valid foreground color");
        }
        else {
            my ( $dark, $light ) = sort { $a <=> $b } ( $foreground, $background );
            cmp_ok( ( $light + 0.05 ) / ( $dark + 0.05 ), '>=', 4.5,
                "$name: header link contrast" );
        }
    }
    else {
        is( $color, 'CanvasText', "$name: uncolored header uses the browser foreground" );
    }

    my $box = declarations( $theme_css, $nav );
    is_deeply(
        [ @{$box}{qw(background border margin)}, declarations( $theme_css, $panel )->{padding} ],
        [ 'transparent', '0', '0', '0' ],
        "$name: header navigation has no sidebar module box"
    );
    my $list = declarations( $theme_css, "$nav ul" );
    is_deeply(
        [ @{$list}{qw(display flex-wrap list-style margin padding)} ],
        [ 'flex', 'wrap', 'none', '0', '0' ],
        "$name: links wrap in an unindented row"
    );
    is( declarations( $theme_css, "$nav li" )->{margin},
        '0', "$name: list items clear module spacing" );
    is( declarations( $theme_css, "$nav a" )->{color},
        'inherit', "$name: links use the header foreground" );

    my ( undef, $sidebar_css ) =
        render_stylesheets( S2::make_context( 1, 2, $theme{$name}, $user{one} ) );
    unlike( $sidebar_css, qr/\.module-navlinks\b/, "$name: theme leaves sidebar navigation alone" );
}

my $unset_header = <<'S2';
layerinfo type = "user";
set module_navlinks_section = "header";
set color_header_background = "";
S2
my $unset_id = ++$layerid;
S2::load_layer( $unset_id, compile_layer( $compiler, $unset_id, 'user', $unset_header ), 0 );
my ( $page_default, $page_theme ) =
    render_stylesheets( S2::make_context( 1, 2, $theme{tabac}, $unset_id ) );
is(
    declarations( $page_theme,   $nav )->{color},
    declarations( $page_default, 'body' )->{color},
    'a transparent header on a dark page can use the readable page foreground'
);

my ($header)  = render_stylesheets( S2::make_context( 1, 2, $theme{kelis}, $user{header} ) );
my ($sidebar) = render_stylesheets( S2::make_context( 1, 2, $theme{kelis}, $user{one} ) );
is_deeply(
    declarations( $header,  '.module a:visited' ),
    declarations( $sidebar, '.module a:visited' ),
    'the shared visited palette is unchanged by navigation placement'
);
unlike( $sidebar, qr/\.module-navlinks/, 'no navigation overrides in sidebar mode' );
is( declarations( $sidebar, '#header .module-wrapper' )->{display},
    'none', 'sidebar mode hides the empty header wrapper' );
is( declarations( $sidebar, '.module-content li' )->{margin}, '.5em 0', 'sidebar item spacing' );
is_deeply(
    declarations( $sidebar, '.module' ),
    declarations( $header,  '.module' ),
    'moving navigation does not change the shared module palette'
);

my $layouts         = read_style('s2layers-core2base.dat');
my @default_header  = qw(basicboxes dustyfoot fiveam lefty planetcaravan summertime);
my @optional_header = qw(practicality tranquilityiii);
my $scoped_nav      = qr/(?:\#header|:where\(\#header\))\s+\.(?:module\.)?module-navlinks\b/;
for my $child ( @default_header, @optional_header ) {
    my ($parent) = $layouts =~ /^\Q$child\E\/layout\s+layout\(([^)]+)\)/m;
    BAIL_OUT("$child no longer inherits Tabula Rasa")
        unless ( $parent // '' ) eq 'core2base/layout';
    my $child_compiler = S2::Compiler->new( {} );
    compile_layer( $child_compiler, 1, 'core', $core );
    my $layout_id = ++$layerid;
    S2::load_layer(
        $layout_id,
        compile_layer(
            $child_compiler, $layout_id, 'layout', $base . read_style("$child/layout.s2")
        ),
        0
    );
    my ($child_theme) =
        read_style("$child/themes.s2") =~ /^#NEWLAYER: \Q$child\E\/\S+\n(.*?)(?=^#NEWLAYER:|\z)/ms;
    BAIL_OUT("Missing a theme for $child") unless defined $child_theme;
    my $theme_id = ++$layerid;
    S2::load_layer( $theme_id, compile_layer( $child_compiler, $theme_id, 'theme', $child_theme ),
        0 );

    my $section = ( grep { $_ eq $child } @optional_header ) ? 'header' : 'default';
    my $ctx     = S2::make_context( 1, $layout_id, $theme_id, $user{$section} );
    is( S2::get_property_value( $ctx, 'module_navlinks_section' ),
        'header', "$child: header navigation is active" );
    my ( $child_default, $child_theme_css ) = render_stylesheets($ctx);
    is( declarations( $child_default, '.module-navlinks li' )->{display},
        'inline-block', "$child: shared CSS preserves the original header item layout" );
    unlike( $child_default, $scoped_nav,
        "$child: shared stylesheet does not style the header module" );
    isnt( declarations( $child_theme_css, "$nav ul" )->{'flex-wrap'},
        'wrap', "$child: theme does not inherit Tabula Rasa wrapping" );
    like(
        $child_default,
        qr/^\.module a:visited\s*\{/m,
        "$child: shared visited palette still applies to header navigation"
    );
}

done_testing;
