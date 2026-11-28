# t/s2-mobile-dustyfoot-easyread.t
#
# Test responsive stylesheet output for Dusty Foot and EasyRead.
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
use DW::Request::Standard;
use HTTP::Request;
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
S2::set_domain('test-mobile-dustyfoot-easyread');
DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/' ) );

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

load_style_layer( 1, 'core', read_style('core2.s2') );

my $layer_id = 1;
for my $layout (qw(dustyfoot easyread)) {
    my $parent = $layout eq 'dustyfoot' ? read_style('core2base/layout.s2') : '';
    load_style_layer( ++$layer_id, 'layout', $parent . read_style("$layout/layout.s2") );

    my $css = '';
    {
        local $S2::pout   = sub { $css .= join '', @_ };
        local $S2::pout_s = $S2::pout;
        my $context = S2::make_context( 1, $layer_id );
        $context->[S2::SCRATCH] = {};
        S2::Builtin::LJ::start_css($context);
        S2::run_code( $context, 'Page::print_default_stylesheet()', { _type => 'EntryPage' } );
        S2::run_code( $context, 'print_stylesheet()' );
        S2::Builtin::LJ::end_css($context);
    }

    my $breakpoint   = $layout eq 'dustyfoot' ? '45em' : '40em';
    my @small_widths = $css =~ /\@media only screen and \(max-width: ([^)]+)\)/g;
    ok(
        @small_widths && !grep( { $_ ne $breakpoint } @small_widths ),
        "$layout uses only its $breakpoint narrow-screen breakpoint"
    );
    like(
        $css,
        qr/\@media only screen and \(min-width: \Q$breakpoint\E\)/,
        "$layout starts medium rules at the same boundary"
    );

    my @mobile = $css =~ /\@media\s+only\s+screen\s+and\s+\(max-width:\s*\Q$breakpoint\E\)\s*\{
        ([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}/gx;

    my %rules;
    for my $mobile (@mobile) {
        while ( $mobile =~ /([^{}]+)\{([^{}]+)\}/g ) {
            my ( $selectors, $declarations ) = ( $1, $2 );
            for my $selector ( split /,/, $selectors ) {
                $selector =~ s/^\s+|\s+$//g;
                $rules{$selector} .= $declarations;
            }
        }
    }

    like( $rules{'#canvas'} // '', qr/\bmargin:\s*0;/,        "$layout removes wide page margins" );
    like( $rules{'#canvas'} // '', qr/\bpadding:\s*0\s+8px;/, "$layout uses 8px page gutters" );
    like( $rules{'#canvas'} // '', qr/\boverflow-wrap:\s*break-word;/, "$layout wraps long words" );
    like( $rules{'.comment-wrapper'} // '',
        qr/\bmin-width:\s*0;/, "$layout lets threaded comments fit the available width" );

    for my $kind (qw(entry comment)) {
        like( $rules{".has-userpic .$kind .header"} // '',
            qr/\bmargin-inline:\s*0;/, "$layout gives the $kind subject the full header width" );
        like( $rules{".$kind-content"} // '',
            qr/\bclear:\s*both;/, "$layout lets wide $kind content start below floated userpics" );
        if ( $layout eq 'dustyfoot' ) {
            like( $rules{".has-userpic .$kind .userpic"} // '',
                qr/\bmargin-top:\s*0;/, "$layout keeps the $kind userpic below the header" );
        }
        unlike(
            $rules{".$kind .contents"} // '',
            qr/\boverflow(?:-x)?:\s*(?:auto|hidden|scroll|clip)\b/,
            "$layout does not scroll the $kind userpic with the text"
        );
    }

    if ( $layout eq 'easyread' ) {
        for my $section (qw(primary secondary tertiary footer)) {
            like( $rules{"#$section"} // '',
                qr/\bpadding-inline:\s*0;/, "$layout adds no gutter padding to #$section" );
        }
        my $poster = $rules{'.has-userpic .entry .poster'} // '';
        like( $poster, qr/\bmargin-inline:\s*0;/, "$layout resets the poster's horizontal offset" );
        like( $poster, qr/\btop:\s*auto;/,        "$layout resets the poster's vertical offset" );
        for my $section (qw(contents footer)) {
            like( $rules{".entry .$section"} // '',
                qr/\bbottom:\s*auto;/, "$layout resets the entry $section offset" );
        }
    }

    for my $selector ( '.entry-content', '.comment-content', '.module-content' ) {
        my $rule = $rules{$selector} // '';
        like( $rule, qr/\boverflow-x:\s*auto;/, "$layout scrolls $selector independently" );
        like( $rule, qr/\bmax-width:\s*100%;/,  "$layout constrains $selector to its parent" );
        like( $rule, qr/\bbox-sizing:\s*border-box;/, "$layout includes padding in $selector" );
    }
}

done_testing;
