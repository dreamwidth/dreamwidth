# t/s2-header-navlinks-lineup-modish.t
#
# Test the header navigation styles in Line Up and Modish.
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
use HTTP::Request;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::BML;
use DW::Request::Standard;
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

sub stylesheets {
    my ($context) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    my $page = { _type => 'Page' };
    S2::run_code( $context, 'Page::print_default_stylesheet()', $page );
    S2::run_code( $context, 'print_stylesheet()' );
    S2::run_code( $context, 'Page::print_theme_stylesheet()',   $page );
    return $css;
}

sub declarations {
    my ( $css, $selector ) = @_;
    return map { /^\s*([\w-]+):\s*(.*?)\s*$/ ? ( $1 => $2 ) : () }
        map    { split /;/ } $css =~ /(?:\A|(?<=[{}]))\s*\Q$selector\E\s*\{([^{}]*)\}/g;
}

sub luminance {
    my ($color) = @_;
    $color =~ s/^#//;
    $color =~ s/(.)/$1$1/g if length $color == 3;
    my @rgb    = map { hex($_) / 255 } $color =~ /(..)/g;
    my @linear = map { $_ <= .04045 ? $_ / 12.92 : ( ( $_ + .055 ) / 1.055 )**2.4 } @rgb;
    return .2126 * $linear[0] + .7152 * $linear[1] + .0722 * $linear[2];
}

sub contrast_ok {
    my ( $css, $label ) = @_;
    my %body   = declarations( $css, 'body' );
    my %header = declarations( $css, '#header' );
    my %nav    = declarations( $css, '#header .module-navlinks' );
    my %link   = declarations( $css, '#header .module-navlinks a' );
    my $hex    = qr/\A(\#[[:xdigit:]]{6}|\#[[:xdigit:]]{3})(?:\s|\z)/;
    my ($background) = map { /$hex/ } grep { defined } (
        $link{'background-color'},
        $header{'background-color'},
        $header{background}, $body{'background-color'},
        $body{background}, '#fff',
    );
    my $foreground = $nav{color} // '';
    my $contrast   = 0;

    if ( $foreground =~ /$hex/ ) {
        my ( $dark, $light ) = sort { $a <=> $b } map { luminance($_) } $foreground, $background;
        $contrast = ( $light + .05 ) / ( $dark + .05 );
    }
    cmp_ok( $contrast, '>=', 4.5, "$label: readable navigation text on its actual background" );
}

DW::Request::Standard->new( HTTP::Request->new( GET => 'http://www.dw.test/' ) );

for my $layout (qw(lineup modish)) {
    my $compiler = S2::Compiler->new( {} );
    S2::set_domain("test-header-navlinks-$layout");
    load_layer( $compiler, 1, 'core', read_style('core2.s2') );
    load_layer( $compiler, 2, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );

    load_layer( $compiler, 3, 'user', <<'S2');
layerinfo type = "user";
set module_navlinks_section = "header";
S2
    load_layer( $compiler, 4, 'user', <<'S2');
layerinfo type = "user";
set module_navlinks_section = "one";
S2
    load_layer( $compiler, 5, 'user', <<'S2');
layerinfo type = "user";
set module_navlinks_section = "header";
set color_header_background = "";
set color_page_background = "";
set color_page_title = "";
set color_page_text = "";
S2

    my $header_css = stylesheets( S2::make_context( 1, 2, 3 ) );
    my %nav        = declarations( $header_css, '#header .module-navlinks' );
    my %list       = declarations( $header_css, '#header .module-navlinks ul' );
    my %items      = declarations( $header_css, '#header .module-navlinks .module-content li' );
    my %links      = declarations( $header_css, '#header .module-navlinks a' );
    is( $nav{background},   'transparent', "$layout: header nav does not inherit module fill" );
    is( $nav{border},       'none',        "$layout: header nav does not inherit module borders" );
    is( $list{'flex-wrap'}, 'wrap',        "$layout: header links can wrap" );
    is( $items{margin}, '0',       "$layout: header links do not inherit module item margins" );
    is( $links{color},  'inherit', "$layout: header links use the navigation color" );

    my $sidebar_css = stylesheets( S2::make_context( 1, 2, 4 ) );
    unlike(
        $sidebar_css,
        qr/#header\s+\.module-navlinks\b/,
        "$layout: sidebar placement does not emit custom header rules"
    );
    my $null_css = stylesheets( S2::make_context( 1, 2, 5 ) );
    contrast_ok( $null_css, "$layout with unset page and header colors" );

    my $theme_id = 5;
    my $themes   = read_style("$layout/themes.s2");
    while ( $themes =~ /^\#NEWLAYER: ([^\n]+)\n(.*?)(?=^\#NEWLAYER:|\z)/msg ) {
        my ( $name, $source ) = ( $1, $2 );
        load_layer( $compiler, ++$theme_id, 'theme', $source );
        contrast_ok( stylesheets( S2::make_context( 1, 2, $theme_id, 3 ) ), $name );
    }
}

done_testing;
