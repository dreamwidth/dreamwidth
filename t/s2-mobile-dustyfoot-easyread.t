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
use DW::BML;
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
    load_style_layer( ++$layer_id, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );

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

    my ($mobile) = $css =~ /\@media\s+only\s+screen\s+and\s+\(max-width:\s*45em\)\s*\{
        ([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}/x;
    ok( defined $mobile, "$layout emits rules specifically for narrow screens" );
    $mobile //= '';

    my %rules;
    while ( $mobile =~ /([^{}]+)\{([^{}]+)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        for my $selector ( split /,/, $selectors ) {
            $selector =~ s/^\s+|\s+$//g;
            $rules{$selector} .= $declarations;
        }
    }

    like( $rules{'#canvas'} // '', qr/\bmargin:\s*0;/, "$layout removes wide page margins" );
    like( $rules{'#canvas'} // '', qr/\bpadding:\s*0\s+\d+px;/, "$layout uses fixed page gutters" );
    like( $rules{'#canvas'} // '', qr/\boverflow-wrap:\s*break-word;/, "$layout wraps long words" );

    for my $kind (qw(entry comment)) {
        like( $rules{".has-userpic .$kind .header"} // '',
            qr/\bmargin-inline:\s*0;/, "$layout gives the $kind subject the full header width" );
        like( $rules{".$kind-content"} // '',
            qr/\bclear:\s*both;/, "$layout lets wide $kind content start below floated userpics" );
        unlike(
            $rules{".$kind .contents"} // '',
            qr/\boverflow(?:-x)?:\s*(?:auto|hidden|scroll|clip)\b/,
            "$layout does not scroll the $kind userpic with the text"
        );
    }

    for my $selector ( '.entry-content', '.comment-content', '.module-content' ) {
        my $rule = $rules{$selector} // '';
        like( $rule, qr/\boverflow-x:\s*auto;/, "$layout scrolls $selector independently" );
        like( $rule, qr/\bmax-width:\s*100%;/,  "$layout constrains $selector to its parent" );
        like( $rule, qr/\bbox-sizing:\s*border-box;/, "$layout includes padding in $selector" );
    }
}

done_testing;
