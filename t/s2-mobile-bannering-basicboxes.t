# t/s2-mobile-bannering-basicboxes.t
#
# Test responsive stylesheet output for Bannering and Basic Boxes.
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

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-mobile-bannering-basicboxes');

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
for my $layout (qw(bannering basicboxes)) {
    load_style_layer( ++$layer_id, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );

    my $css = '';
    {
        local $S2::pout   = sub { $css .= join '', @_ };
        local $S2::pout_s = $S2::pout;
        my $context = S2::make_context( 1, $layer_id );
        $context->[S2::SCRATCH] = {};
        S2::Builtin::LJ::start_css($context);
        S2::run_code( $context, 'print_stylesheet()' );
        S2::Builtin::LJ::end_css($context);
    }

    my ($mobile) = $css =~ /\@media\s+only\s+screen\s+and\s+\(max-width:\s*[^)]+\)\s*\{
        ([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}/x;
    ok( defined $mobile, "$layout emits a narrow-screen stylesheet" );
    $mobile //= '';

    my %rules;
    while ( $mobile =~ /([^{}]+)\{([^{}]+)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        for my $selector ( split /,/, $selectors ) {
            $selector =~ s/^\s+|\s+$//g;
            $rules{$selector} .= $declarations;
        }
    }

    like(
        $rules{'#canvas'} // '',
        qr/\bmargin-inline:\s*0(?:;|\s*\z)/,
        "$layout removes customizable page margins on narrow screens"
    );
    for my $selector ( '.entry-content', '.comment-content', '#content .module-content' ) {
        like(
            $rules{$selector} // '',
            qr/\boverflow-x:\s*auto(?:;|\s*\z)/,
            "$layout contains wide content in $selector"
        );
    }

    for my $kind (qw(entry comment)) {
        my $userpic = $layout eq 'bannering' ? ".$kind .userpic" : ".$kind .contents .userpic";
        like(
            $rules{".has-userpic $userpic"} // '',
            qr/\bmargin-top:\s*0(?:;|\s*\z)/,
            "$layout keeps the $kind icon below the header"
        );
        like(
            $rules{".$kind-content"} // '',
            qr/\bclear:\s*both(?:;|\s*\z)/,
            "$layout prevents wide $kind content from overlapping the icon"
        );
        if ( $layout eq 'bannering' ) {
            like(
                $rules{".has-userpic .$kind .header"} // '',
                qr/\bmargin-inline:\s*0(?:;|\s*\z)/,
                "$layout gives the $kind subject the full header width"
            );
        }
    }
}

done_testing;
