# t/s2-header-navlinks-paperme-refriedtablet.t
#
# Check header navigation styles for Paper Me and Refried Tablet.
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

my $compiler = S2::Compiler->new( {} );
my $next_id  = 0;
S2::set_domain('test-header-navlinks-paperme-refriedtablet');

sub read_style {
    my ($path) = @_;
    open my $file, '<', "$ENV{LJHOME}/styles/$path" or die "Cannot open $path: $!";
    local $/;
    return <$file>;
}

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

sub render_css {
    my ( $ctx, $function, @args ) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, $function, @args );
    return $css;
}

sub rule {
    my ( $css, $selector ) = @_;
    return ( $css =~ /^\s*\Q$selector\E\s*\{([^{}]*)\}/m )[0] // '';
}

sub color_value {
    my ( $rule, $property ) = @_;
    return ( $rule =~ /(?:^|;)\s*\Q$property\E:\s*(#[\da-f]+)\s*;/i )[0];
}

sub luminance {
    my ($color) = @_;
    return unless defined $color;
    $color =~ s/\A#//;
    $color =~ s/(.)/$1$1/g if length($color) == 3;
    return unless length($color) == 6;
    my @channels = map { hex($_) / 255 } $color =~ /(..)/g;
    @channels = map { $_ <= 0.04045 ? $_ / 12.92 : ( ( $_ + 0.055 ) / 1.055 )**2.4 } @channels;
    return 0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2];
}

my $core = load_layer( 'core', read_style('core2.s2') );
my $base = read_style('core2base/layout.s2');
my $header =
    load_layer( 'user', 'layerinfo type = "user"; set module_navlinks_section = "header";' );
my $sidebar = load_layer( 'user', 'layerinfo type = "user"; set module_navlinks_section = "one";' );
my $unset   = load_layer( 'user', <<'S2' );
layerinfo type = "user";
set module_navlinks_section = "header";
set color_page_title = "";
set color_page_text = "";
set color_header_background = "";
set color_page_background = "";
S2
my $nav = '#header .module-navlinks';

for my $name (qw(paperme refriedtablet)) {
    my $layout = load_layer( 'layout', $base . read_style("$name/layout.s2") );
    my @themes = split /^#NEWLAYER:\s+(\S+)\n/m, read_style("$name/themes.s2");
    shift @themes;
    BAIL_OUT("No themes for $name") unless @themes;

    my $sidebar_ctx = S2::make_context( $core, $layout, $sidebar );
    like(
        rule(
            render_css( $sidebar_ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } ),
            '#header .module-wrapper'
        ),
        qr/display:\s*none;/,
        "$name: sidebar placement does not display a header module"
    );

    while (@themes) {
        my ( $theme_name, $theme_source ) = splice @themes, 0, 2;
        my $theme = load_layer( 'theme', $theme_source );
        subtest $theme_name => sub {
            my $ctx = S2::make_context( $core, $layout, $theme, $header );
            my $base_css =
                render_css( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );
            my $layout_css = render_css( $ctx, 'print_stylesheet()' );

            my $box = rule( $layout_css, $nav );
            like( $box, qr/background:\s*transparent;/, 'no sidebar background on the header box' );
            like( $box, qr/border:\s*none;/,            'no sidebar border on the header box' );
            like( rule( $layout_css, "$nav li" ), qr/margin:\s*0;/, 'no sidebar list margins' );
            like(
                rule( $layout_css, "$nav .module-list" ),
                qr/flex-wrap:\s*wrap;/,
                'navigation can wrap in a narrow header'
            );

            my $link       = rule( $layout_css, "$nav a" );
            my $foreground = luminance( color_value( $link, 'color' ) );
            my $background = luminance(
                $name eq 'paperme'
                ? color_value( $link, 'background-color' )
                : color_value( rule( $base_css, '#header' ), 'background' )
            );
            if ( defined $foreground && defined $background ) {
                my ( $dark, $light ) = sort { $a <=> $b } ( $foreground, $background );
                cmp_ok( ( $light + 0.05 ) / ( $dark + 0.05 ),
                    '>=', 4.5, 'navigation text has sufficient contrast on its surface' );
            }
            else {
                fail('navigation text and its surface have usable colors');
            }
        };
    }

    my $null_ctx  = S2::make_context( $core, $layout, $unset );
    my $null_css  = render_css( $null_ctx, 'print_stylesheet()' );
    my $null_link = rule( $null_css, "$nav a" );
    ok(
        defined color_value( $null_link, 'color' ),
        "$name: unset colors still produce a link color"
    );
}

done_testing;
