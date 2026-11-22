# t/s2-header-navlinks-tabularasa.t
#
# Test the header navigation stylesheet shared by Tabula Rasa layouts.
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
    my $ctx = S2::make_context(@_);
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $ctx, 'Page::print_theme_stylesheet()',   { _type => 'Page' } );
    return $css;
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
for my $section ( 'header', 'one' ) {
    my $id     = $user{$section} = ++$layerid;
    my $source = qq{layerinfo type = "user"; set module_navlinks_section = "$section";};
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
    if grep { !exists $theme{$_} } qw(kelis nnwm2009 tabac testing);

my $nav   = ':where(#header) .module-navlinks';
my $panel = ':where(#header) .module.module-navlinks';
for my $name ( sort keys %theme ) {
    my $css        = render_stylesheets( 1, 2, $theme{$name}, $user{header} );
    my $color      = declarations( $css, $nav )->{color};
    my $header     = declarations( $css, '#header' );
    my $body       = declarations( $css, 'body' );
    my $background = luminance( $header->{'background-color'} // $header->{background} );
    $background //= luminance( $body->{'background-color'} // $body->{background} );
    if ( defined $background ) {
        my $foreground = luminance($color);
        if ( !defined $foreground ) {
            fail("$name: header navigation has a valid foreground color");
            next;
        }
        my ( $dark, $light ) = sort { $a <=> $b } ( $foreground, $background );
        cmp_ok( ( $light + 0.05 ) / ( $dark + 0.05 ), '>=', 4.5, "$name: header link contrast" );
    }
    else {
        is( $color, 'CanvasText', "$name: uncolored header uses the browser foreground" );
    }
}

my $unset_header = <<'S2';
layerinfo type = "user";
set module_navlinks_section = "header";
set color_header_background = "";
S2
my $unset_id = ++$layerid;
S2::load_layer( $unset_id, compile_layer( $compiler, $unset_id, 'user', $unset_header ), 0 );
my $page_backdrop = render_stylesheets( 1, 2, $theme{tabac}, $unset_id );
is(
    declarations( $page_backdrop, $nav )->{color},
    declarations( $page_backdrop, 'body' )->{color},
    'a transparent header on a dark page can use the readable page foreground'
);

my $header  = render_stylesheets( 1, 2, $theme{kelis}, $user{header} );
my $sidebar = render_stylesheets( 1, 2, $theme{kelis}, $user{one} );
my $box = declarations( $header, $nav );
is_deeply(
    [ @{$box}{qw(background border margin)} ],
    [ 'transparent', '0', '0' ],
    'header navigation does not paint a sidebar module box'
);
is( declarations( $header, $panel )->{padding},
    '0', 'header navigation clears theme module padding' );
my $list = declarations( $header, "$nav ul" );
is_deeply(
    [ @{$list}{qw(display flex-wrap list-style margin padding)} ],
    [ 'flex', 'wrap', 'none', '0', '0' ],
    'header links wrap in an unindented row'
);
is( declarations( $header, "$nav li" )->{margin}, '0', 'header items reset module list spacing' );
is( declarations( $header, "$nav a" )->{color}, 'inherit', 'links use the header foreground' );
is_deeply(
    declarations( $header,  '.module:not(:where(#header .module-navlinks)) a:visited' ),
    declarations( $sidebar, '.module a:visited' ),
    'the sidebar visited palette does not apply to header links'
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

my $layouts = read_style('s2layers-core2base.dat');
for my $child (
    qw(ciel colorside fluidmeasure forthebold funkycircles lineup modish paperme
    refriedtablet snakesandboxes steppingstones tranquilityiii)
    )
{
    my ($parent) = $layouts =~ /^\Q$child\E\/layout\s+layout\(([^)]+)\)/m;
    BAIL_OUT("$child no longer inherits Tabula Rasa")
        unless ( $parent // '' ) eq 'core2base/layout';
    my $child_compiler = S2::Compiler->new( {} );
    compile_layer( $child_compiler, 1, 'core', $core );
    ok(
        eval {
            compile_layer( $child_compiler, 2, 'layout', $base . read_style("$child/layout.s2") );
        },
        "$child compiles with its inherited layout"
    ) or diag($@);
}

done_testing;
