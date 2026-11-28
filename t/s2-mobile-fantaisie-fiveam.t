# t/s2-mobile-fantaisie-fiveam.t
#
# Test narrow-screen stylesheets for Fantaisie and Five AM.
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
S2::set_domain('test-mobile-fantaisie-fiveam');

sub read_style {
    my ($file) = @_;
    open my $source, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$source>;
}

sub load_style {
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

sub declarations_for {
    my ( $css, $selector ) = @_;
    my $declarations = '';
    while ( $css =~ /\s*([^{}]+?)\s*\{([^{}]*)\}/g ) {
        my ( $selectors, $body ) = ( $1, $2 );
        $declarations .= $body if grep { $_ eq $selector } split /\s*,\s*/, $selectors;
    }
    return $declarations;
}

sub mobile_css {
    my ( $context, $breakpoint ) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'print_stylesheet()' );
    $css =~ s{/\*.*?\*/}{}gs;
    my ($mobile) = $css =~
        /\@media only screen and \(max-width: \Q$breakpoint\E\)\s*\{((?:[^{}]*\{[^{}]*\})*\s*)\}/;
    return $mobile // '';
}

load_style( 1, 'core', read_style('core2.s2') );
my $layer_id           = 1;
my %default_breakpoint = ( fantaisie => '45em', fiveam => '51em' );
for my $layout (qw(fantaisie fiveam)) {
    subtest $layout => sub {
        my $layout_id = ++$layer_id;
        load_style( $layout_id, 'layout',
            read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );
        my $breakpoint = $default_breakpoint{$layout};
        my $mobile     = mobile_css( S2::make_context( 1, $layout_id ), $breakpoint );
        ok( length $mobile, "emits a narrow-screen stylesheet at $breakpoint" );

        my $user_id = ++$layer_id;
        load_style( $user_id, 'user',
            'layerinfo type = "user"; set medium_breakpoint_width = "37em";' );
        my $custom = mobile_css( S2::make_context( 1, $layout_id, $user_id ), '37em' );
        like( declarations_for( $custom, '#canvas' ),
            qr/\bmargin-inline:\s*0;/, 'narrow-screen gutters follow a custom column breakpoint' );

        my $canvas = declarations_for( $mobile, '#canvas' );
        like( $canvas, qr/\bmargin-inline:\s*0;/, 'disables full-page side margins' );
        like( declarations_for( $mobile, '.comment-wrapper' ),
            qr/\bmin-width:\s*0;/, 'nested comments can shrink to fit their indented column' );
        my $gutter = $layout eq 'fantaisie' ? declarations_for( $mobile, '#content' ) : $canvas;
        like( $gutter, qr/\bpadding-inline:\s*[1-9]\d?px;/, 'uses fixed-width gutters' );
        if ( $layout eq 'fantaisie' ) {
            like( $gutter, qr/\bmargin-inline:\s*0;/, 'removes the percentage content margins' );
            for my $selector ( '.navigation', '.page-top .inner' ) {
                like( declarations_for( $mobile, $selector ),
                    qr/\bmargin-inline:\s*0;/, "$selector ornament stays inside the page" );
            }
            my $module = declarations_for( $mobile, '#content .module' );
            like( $module, qr/\bmax-width:\s*100%;/, 'fixed-width modules can shrink to fit' );
            like( $module, qr/\bbox-sizing:\s*border-box;/, 'module width includes its padding' );
            like( declarations_for( $mobile, '.page-read .has-userpic .entry-content' ),
                qr/\bpadding-inline:\s*0;/,
                'reading-page text no longer reserves space for the userpic' );
        }
        else {
            like( declarations_for( $mobile, '.has-userpic .entry .contents' ),
                qr/\bmargin-inline:\s*0;/, 'entry text no longer reserves space for the userpic' );
            like( declarations_for( $mobile, '.entry .datetime' ),
                qr/\bfloat:\s*none;/,
                'timestamp does not compete with the entry subject for width' );
        }

        for my $kind (qw(entry comment)) {
            like(
                declarations_for( $mobile, ".$kind .header" ),
                qr/\boverflow-wrap:\s*break-word;/,
                "$kind header wraps long subjects"
            );
            like( declarations_for( $mobile, ".$kind-content" ),
                qr/\bclear:\s*both;/, "$kind text starts below the userpic float" );
        }

        for my $kind (qw(entry comment module)) {
            my $content = declarations_for( $mobile, ".$kind-content" );
            like( $content, qr/\boverflow-x:\s*auto;/, "$kind content scrolls independently" );
            like( $content, qr/\bmax-width:\s*100%;/,  "$kind content is bounded by its parent" );
            like( $content, qr/\bbox-sizing:\s*border-box;/, "$kind width includes its padding" );
        }
    };
}

done_testing;
