# t/s2-tectonic-navlinks.t
#
# Test contrast in the compiled Tectonic navigation stylesheet.
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

sub read_source {
    my ($file) = @_;
    open my $source, '<:raw', "$ENV{LJHOME}/styles/$file" or die "Cannot read $file: $!";
    local $/;
    return <$source>;
}

my $compiler      = S2::Compiler->new( {} );
my $next_layer_id = 0;

sub compile_layer {
    my ( $type, $source ) = @_;
    my $layer_id = ++$next_layer_id;
    my $compiled;
    $compiler->compile_source(
        {
            type           => $type,
            source         => \$source,
            output         => \$compiled,
            layerid        => $layer_id,
            builtinPackage => 'S2::Builtin::LJ',
        }
    );
    S2::load_layer( $layer_id, $compiled );
    return $layer_id;
}

sub luminance {
    my ($color) = @_;
    return unless defined $color && $color =~ /\A#([[:xdigit:]]{3}|[[:xdigit:]]{6})\z/;
    my $hex = $1;
    $hex =~ s/(.)/$1$1/g if length($hex) == 3;
    my ( $red, $green, $blue ) = map {
        my $srgb = hex($_) / 255;
        $srgb <= 0.04045 ? $srgb / 12.92 : ( ( $srgb + 0.055 ) / 1.055 )**2.4;
    } $hex =~ /(..)/g;
    return 0.2126 * $red + 0.7152 * $green + 0.0722 * $blue;
}

sub check_contrast {
    my ( $text, $background, $state ) = @_;
    my $foreground_luminance = luminance($text);
    my $background_luminance = luminance($background);
    unless ( defined $foreground_luminance && defined $background_luminance ) {
        fail("$state emits valid text and background colors");
        return;
    }
    my ( $dark, $light ) = sort { $a <=> $b } ( $foreground_luminance, $background_luminance );
    cmp_ok( ( $light + 0.05 ) / ( $dark + 0.05 ), '>=', 4.5, "$state has readable contrast" );
}

sub declaration {
    my ( $css, $selector, $name ) = @_;
    my ($rule)  = $css =~ /^\h*\Q$selector\E\s*\{([^}]*)\}/m;
    my ($value) = ( $rule // '' ) =~ /(?:\A|;)\s*\Q$name\E:\s*([^;}]*)/;
    return defined $value ? $value =~ s/\s+\z//r : undef;
}

S2::set_domain('tectonic-navlinks-test');
my $layout_source = read_source('core2base/layout.s2') . read_source('tectonic/layout.s2');
my @base          = ( compile_layer( 'core', read_source('core2.s2') ),
    compile_layer( 'layout', $layout_source ), );

sub stylesheet {
    my $context = S2::make_context( @base, @_ );
    my $css     = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'prop_init()' );
    S2::run_code( $context, 'print_stylesheet()' );
    return $css;
}

for my $source ( grep { /layerinfo type/ } split /^#NEWLAYER:.*\n/m,
    read_source('tectonic/themes.s2') )
{
    my ($theme) = $source =~ /layerinfo name = "([^"]+)"/;
    subtest $theme => sub {
        my $css        = stylesheet( compile_layer( 'theme', $source ) );
        my $background = declaration( $css, '.module-navlinks.module li', 'background' );
        my $hover_background =
            declaration( $css, '.module-navlinks.module li:hover', 'background' );
        check_contrast( declaration( $css, '.module-navlinks a', 'color' ), $background,
            'default' );
        check_contrast( declaration( $css, '.module-navlinks a:visited', 'color' ),
            $background, 'visited' );
        check_contrast( declaration( $css, '.module-navlinks a:hover', 'color' ),
            $hover_background, 'hover' );
        check_contrast( declaration( $css, '.module-navlinks a:active', 'color' ),
            $hover_background, 'active' );
    };
}

subtest 'custom navbar colors' => sub {
    my $css = stylesheet( compile_layer( 'theme', <<'S2' ) );
layerinfo type = "theme";
set color_header_links = "#112233";
set color_header_links_background = "#ffffff";
set color_header_links_visited = "#223344";
set color_header_links_hover = "#334455";
S2
    is( declaration( $css, '.module-navlinks a:visited', 'color' ),
        '#223344', 'keeps visited override' );
    is( declaration( $css, '.module-navlinks a:hover', 'color' ),
        '#334455', 'keeps hover override' );
    is( declaration( $css, '.module-navlinks a:active', 'color' ),
        '#112233', 'falls back to custom base color' );
};

done_testing();
