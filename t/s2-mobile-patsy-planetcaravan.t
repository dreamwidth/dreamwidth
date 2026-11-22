# t/s2-mobile-patsy-planetcaravan.t
#
# Test narrow-screen stylesheets for Patsy and Planet Caravan.
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
use LJ::CSS::Cleaner;
use LJ::S2;
use S2;
use S2::Compiler;

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-mobile-patsy-planetcaravan');

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
    while ( $css =~ /([^{}]+)\{([^{}]*)\}/g ) {
        my ( $selectors, $body ) = ( $1, $2 );
        $selectors =~ s/^\s+|\s+$//g;
        $declarations .= $body if grep { $_ eq $selector } split /\s*,\s*/, $selectors;
    }
    return $declarations;
}

sub check_breakpoints {
    my ( $context, $configuration ) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'print_stylesheet()' );
    $css = LJ::CSS::Cleaner->new->clean($css);

    my $medium  = S2::run_function( $context, 'generate_medium_media_query()' );
    my $narrow  = $medium =~ s/and \(/and not (/r;
    my %queries = map { $_ => 1 } $css =~ /^\s*\@media (only screen and [^{]+?)\s*\{/mg;
    is_deeply(
        [ sort keys %queries ],
        [ sort( $narrow, $medium ) ],
        "$configuration: mobile stops strictly below the unmodified desktop breakpoint"
    );

    my ($mobile) = $css =~ /\@media \Q$narrow\E\s*\{((?:[^{}]*\{[^{}]*\})*\s*)\}/;
    return $mobile // '';
}

load_style( 1, 'core', read_style('core2.s2') );
my $core2base = read_style('core2base/layout.s2');
my $layer_id  = 1;
for my $layout (qw(patsy planetcaravan)) {
    subtest $layout => sub {
        my $layout_id = ++$layer_id;
        load_style( $layout_id, 'layout', $core2base . read_style("$layout/layout.s2") );
        my $mobile = check_breakpoints( S2::make_context( 1, $layout_id ), 'default' );

        for my $setting ( 'sidebar_width = "12em"', 'medium_breakpoint_width = "820px"' ) {
            load_style( ++$layer_id, 'user', qq{layerinfo type = "user"; set $setting;} );
            check_breakpoints( S2::make_context( 1, $layout_id, $layer_id ), $setting );
        }

        my $canvas = declarations_for( $mobile, '#canvas' );
        like( $canvas, qr/\bmargin-inline:\s*0;/,           'removes configurable page gutters' );
        like( $canvas, qr/\bpadding-inline:\s*[1-9]\d?px;/, 'uses fixed page gutters' );
        if ( $layout eq 'planetcaravan' ) {
            like(
                declarations_for( $mobile, '#content' ),
                qr/\bmargin-inline:\s*0;/,
                'removes the percentage content margin'
            );
        }
        else {
            like(
                declarations_for( $mobile, '#header' ),
                qr/\btext-align:\s*start;/,
                'journal title is not justified'
            );
        }

        like( declarations_for( $mobile, '.comment-wrapper' ),
            qr/\bmin-width:\s*0;/, 'nested comments can shrink past the desktop minimum' );
        like( declarations_for( $mobile, '.icons-container .icon' ),
            qr/\bmin-width:\s*0;/, 'icon rows can shrink past the desktop minimum' );

        for my $kind (qw(entry comment)) {
            my $header = declarations_for( $mobile, ".$kind .header" );
            like( $header, qr/\bmargin-inline:\s*0;/,          "$kind header uses the full width" );
            like( $header, qr/\boverflow-wrap:\s*break-word;/, "$kind header wraps long subjects" );
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
