# t/s2-header-navlinks-crisped-fluidmeasure.t
#
# Test header navigation styles in Crisped and Fluid Measure.
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

sub load_style {
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
    my ($ctx) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'prop_init()' );
    S2::run_code( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    S2::run_code( $ctx, 'print_stylesheet()' );
    return $css;
}

sub luminance {
    my ($hex) = @_;
    my @weights = ( 0.2126, 0.7152, 0.0722 );
    my $total   = 0;
    for my $component ( $hex =~ /([0-9a-f]{2})/gi ) {
        my $value = hex($component) / 255;
        $total += shift(@weights) *
            ( $value <= 0.04045 ? $value / 12.92 : ( ( $value + 0.055 ) / 1.055 )**2.4 );
    }
    return $total;
}

my $nav = '#header .module-navlinks';

sub declarations {
    my ( $css, $selector ) = @_;
    my ($block) = $css =~ /\Q$selector\E\s*\{([^}]*)\}/;
    return $block // '';
}

for my $layout (qw(crisped fluidmeasure)) {
    S2::set_domain("test-navlinks-$layout");
    my $compiler = S2::Compiler->new( {} );
    load_style( $compiler, 1, 'core', read_style('core2.s2') );
    load_style( $compiler, 2, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );
    for my $placement ( [ 3, 'header' ], [ 4, 'one' ] ) {
        my ( $id, $section ) = @$placement;
        load_style(
            $compiler, $id, 'user', qq{
            layerinfo type = "user";
            set module_navlinks_section = "$section";
            set custom_control_strip_colors = "off";
        }
        );
    }

    my $header  = render_stylesheets( S2::make_context( 1, 2, 3 ) );
    my $sidebar = render_stylesheets( S2::make_context( 1, 2, 4 ) );
    my $module = declarations( $header, $nav );
    like(
        $module,
        qr/background:\s*transparent;/,
        "$layout: header nav drops the module background"
    );
    like( $module, qr/border:\s*none;/, "$layout: header nav drops the module border" );
    like( $module, qr/color:\s*inherit;/,
        "$layout: an unset palette yields a valid inherited color" );
    my $list = declarations( $header, "$nav .module-list" );
    like( $list, qr/display:\s*flex;/,   "$layout: header links form a row" );
    like( $list, qr/flex-wrap:\s*wrap;/, "$layout: header links can form more rows" );
    like( $list, qr/margin:\s*0;/,       "$layout: header list has no inherited indentation" );
    like( declarations( $header, "$nav li" ),
        qr/margin:\s*0;/, "$layout: header list items have no inherited module margins" );
    unlike( $sidebar, qr/\Q$nav\E/, "$layout: sidebar mode omits the header nav overrides" );

    my $themes = read_style("$layout/themes.s2");
    my $id     = 4;
    while ( $themes =~ /^\#NEWLAYER: (\S+)\n(.*?)(?=^\#NEWLAYER:|\z)/msg ) {
        my ( $name, $source ) = ( $1, $2 );
        load_style( $compiler, ++$id, 'theme', $source );
        my $ctx = S2::make_context( 1, 2, $id, 3 );
        my $css = render_stylesheets($ctx);
        my ($foreground) = declarations( $css, $nav ) =~ /(?:^|\s)color:\s*(\#[0-9a-f]{6});/i;
        my ($background) =
            grep { defined && length }
            map { ( S2::get_property_value( $ctx, $_ ) // {} )->{as_string} } (
            'color_header_background',
            $layout eq 'fluidmeasure' ? 'color_entry_title_background' : (),
            'color_page_background'
            );
        my $contrast = 0;
        if ( defined $foreground && defined $background ) {
            my ( $dark, $light ) =
                sort { $a <=> $b } map { luminance($_) } ( $foreground, $background );
            $contrast = ( $light + 0.05 ) / ( $dark + 0.05 );
        }
        cmp_ok( $contrast, '>=', 4.5, "$name: header nav text contrasts with its background" );
    }
}

done_testing;
