# t/s2-mobile-hibiscus-marginless.t
#
# Test narrow-screen stylesheets for Hibiscus and Marginless.
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
S2::set_domain('test-mobile-hibiscus-marginless');

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

load_style( 1, 'core', read_style('core2.s2') );
my $layout_id = 1;
for my $layout (qw(hibiscus marginless)) {
    subtest $layout => sub {
        load_style( ++$layout_id, 'layout',
            read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );
        my $context = S2::make_context( 1, $layout_id );
        $context->[S2::SCRATCH] = {};
        my $css = '';
        local $S2::pout   = sub { $css .= join '', @_ };
        local $S2::pout_s = $S2::pout;
        S2::Builtin::LJ::start_css($context);
        S2::run_code( $context, 'print_stylesheet()' );
        S2::Builtin::LJ::end_css($context);

        my ( $limit, $excluded_limit, $mobile ) = $css =~ /
            \@media\s+only\s+screen\s+and\s+\(max-width:\s*(\d+)em\)
            \s+and\s+\(not\s+\(min-width:\s*(\d+)em\)\)\s*
            \{((?:[^{}]*\{[^{}]*\})*\s*)\}
        /x;
        my ($desktop_limit) = $css =~ /\@media only screen and \(min-width: (\d+)em\)/;
        is( $limit, $layout eq 'hibiscus' ? 45 : 36,
            'emits the layout-specific mobile breakpoint' );
        is( $excluded_limit, $desktop_limit, 'mobile rules stop before the desktop breakpoint' );
        $mobile //= '';

        my $module = '#content .module';
        if ( $layout eq 'marginless' ) {
            my $tablet_width = 600 / 16;
            ok(
                defined $limit
                    && defined $desktop_limit
                    && $limit <= $tablet_width
                    && $desktop_limit <= $tablet_width,
                'at 600px only the desktop query matches'
            );
            like(
                declarations_for( $mobile, '#primary > .inner:first-child' ),
                qr/\bpadding-inline:\s*[1-9]\d?px;/,
                'keeps an inset inside the content panel'
            );
        }
        else {
            $module = ".any-column $module";
        }
        like( declarations_for( $mobile, $module ),
            qr/\bmax-width:\s*100%;/, 'bounds the module itself by the available width' );

        my $canvas = declarations_for( $mobile, '#canvas' );
        like( $canvas, qr/\bmargin-inline:\s*0;/,           'disables configurable page gutters' );
        like( $canvas, qr/\bpadding-inline:\s*[1-9]\d?px;/, 'uses fixed page gutters' );
        if ( $layout eq 'hibiscus' ) {
            like(
                declarations_for( $mobile, '#content' ),
                qr/\bmargin-inline:\s*0;/,
                'removes the percentage content margin'
            );
        }

        for my $kind (qw(entry comment)) {
            my $header = declarations_for( $mobile, ".$kind .header" );
            like( $header, qr/\bmargin-inline:\s*0;/,          "$kind header uses the full width" );
            like( $header, qr/\boverflow-wrap:\s*break-word;/, "$kind header wraps long subjects" );
            like( declarations_for( $mobile, ".$kind-content" ),
                qr/\bclear:\s*both;/, "$kind text starts below the userpic float" );
        }

        for my $kind (qw(entry comment module)) {
            my $content = declarations_for( $mobile, ".$kind-content" );
            like( $content, qr/\boverflow-x:\s*auto;/, "$kind content scrolls independently" );
            like( $content, qr/\bmax-width:\s*100%;/,  "$kind content is bounded by its parent" );
            like(
                $content,
                qr/\bbox-sizing:\s*border-box;/,
                "$kind content includes its own padding"
            );
        }
    };
}

done_testing;
