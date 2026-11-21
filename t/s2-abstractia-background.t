# t/s2-abstractia-background.t
#
# Test the CSS emitted for Abstractia page backgrounds.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Image::Size qw(imgsize);
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

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-abstractia-background');

sub load_style_layer {
    my ( $id, $type, $source ) = @_;
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

sub page_background_css {
    my (@layers) = @_;
    my $ctx = S2::make_context( 1, 2, @layers );
    LJ::S2::populate_system_props($ctx);
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'Page::print_default_stylesheet()', { _type => 'Page' } );
    my ($body) = $css =~ /^body\s*\{([^}]*background-attachment: fixed;[^}]*)\}/m;
    return $body // die 'Abstractia stylesheet is missing its fixed body background';
}

load_style_layer( 1, 'core',   read_style('core2.s2') );
load_style_layer( 2, 'layout', read_style('abstractia/layout.s2') );

my $themes   = read_style('abstractia/themes.s2');
my $layer_id = 10;
my $abyss_id;
while ( $themes =~ /^#NEWLAYER: (\S+)\s*\n(.*?)(?=^#NEWLAYER:|\z)/msg ) {
    my ( $name, $source ) = ( $1, $2 );
    my ($image)  = $source =~ /^set image_background_page_url = "([^"]+)";/m;
    my ($repeat) = $source =~ /^set image_background_page_repeat = "([^"]+)";/m;
    load_style_layer( ++$layer_id, 'theme', $source );
    $abyss_id = $layer_id if $name eq 'abstractia/abyss';
    my $body = page_background_css($layer_id);
    if ( $image && ( $repeat // '' ) eq 'no-repeat' ) {
        my ( $width, $height ) = imgsize("$ENV{LJHOME}/htdocs/img/styles/$image");
        BAIL_OUT("Cannot read the dimensions of $image") unless $width && $height;
        my $size = "max(100%, ${width}px, calc(100vh * $width / $height)) auto";
        like(
            $body,
            qr/background-size:\s*\Q$size\E;/,
            "$name fills wide and tall viewports without shrinking below its original size"
        );
    }
    else {
        unlike( $body, qr/background-size:/, "$name keeps its original background sizing" );
    }
}

BAIL_OUT('Abyss is missing') unless $abyss_id;
for my $repeat ( 'repeat', 'repeat-x', 'repeat-y' ) {
    load_style_layer( ++$layer_id, 'user',
        qq{layerinfo type = "user"; set image_background_page_repeat = "$repeat";} );
    my $body = page_background_css( $abyss_id, $layer_id );
    unlike( $body, qr/background-size:/, "User-selected $repeat keeps the original image size" );
    like(
        $body,
        qr/url\([^)]*abyss-page\.jpg\)\s+\Q$repeat\E\s/,
        "User-selected $repeat reaches the stylesheet"
    );
}

my $custom_url = 'https://images.example/background.jpg';
load_style_layer( ++$layer_id, 'user',
    qq{layerinfo type = "user"; set image_background_page_url = "$custom_url";} );
my $custom_body = page_background_css( $abyss_id, $layer_id );
unlike( $custom_body, qr/background-size:/,
    'An uploaded background keeps its original image size' );
like(
    $custom_body,
    qr/url\(\Q$custom_url\E\)\s+no-repeat\s/,
    'An uploaded background retains its no-repeat setting'
);

done_testing;
