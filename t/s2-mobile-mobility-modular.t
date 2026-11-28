# t/s2-mobile-mobility-modular.t
#
# Check mobile layout and overflow rules emitted by Mobility and Modular.
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

sub load_layer {
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

sub check_mobile_breakpoint {
    my ( $ctx, $expected_width, $label ) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'print_stylesheet()' );

    my ($medium_width) =
        S2::run_function( $ctx, 'generate_medium_media_query()' ) =~ /\(min-width: ([^)]+)\)/;
    my ( $small_width, $mobile );
    while ( $css =~ /^([ \t]*)\@media only screen and \(max-width: ([^)]+)\)\s*\{(.*?)^\1\}/gms ) {
        my ( $width, $body ) = ( $2, $3 );
        next unless $body =~ /^\s*body #canvas\s*\{/m;
        ( $small_width, $mobile ) = ( $width, $body );
        last;
    }
    is( $small_width, $expected_width, "$label: mobile rules use the expected breakpoint" );
    ok( defined $small_width && defined $medium_width && $small_width eq $medium_width,
        "$label: mobile and medium queries share only the boundary" );
    return {} unless defined $mobile;
    my %rules;
    while ( $mobile =~ /([^{}]+)\{([^{}]+)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        for my $selector ( split /\s*,\s*/, $selectors ) {
            $selector =~ s/^\s+|\s+$//g;
            $rules{$selector} .= $declarations;
        }
    }
    return \%rules;
}

for my $layout (qw(mobility modular)) {
    my $compiler = S2::Compiler->new( {} );
    S2::set_domain("test-mobile-$layout");
    load_layer( $compiler, 1, 'core', read_style('core2.s2') );
    load_layer( $compiler, 2, 'layout',
        read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );

    my $ctx   = S2::make_context( 1, 2 );
    my $rules = check_mobile_breakpoint( $ctx, $layout eq 'mobility' ? '30em' : '45em', $layout );
    like(
        $rules->{'body #canvas'} // '',
        qr/padding:\s*0 8px;/,
        "$layout: compact fixed page gutters on mobile"
    );
    like( $rules->{'.comment-wrapper'} // '',
        qr/min-width:\s*0;/, "$layout: nested comment wrappers can shrink on mobile" );

    for my $kind (qw(entry comment)) {
        like(
            $rules->{".$kind .header"} // '',
            qr/overflow-wrap:\s*break-word;/,
            "$layout: long $kind subjects wrap on mobile"
        );
    }

    for my $kind (qw(entry comment module)) {
        my $content = $rules->{".$kind-content"} // '';
        like( $content, qr/overflow-x:\s*auto;/, "$layout: $kind overflow scrolls locally" );
        like( $content, qr/max-width:\s*100%;/,  "$layout: $kind content fits its container" );
        like( $content, qr/box-sizing:\s*border-box;/, "$layout: $kind includes padding in width" );
    }

    if ( $layout eq 'mobility' ) {
        like( $rules->{'.entry .header'} // '',
            qr/margin-right:\s*0;/, 'mobility: no fixed userpic allowance in the entry header' );
    }
    else {
        like( $rules->{'.comment'} // '',
            qr/min-width:\s*0;/, 'modular: nested comment boxes can shrink on mobile' );
        for my $selector (
            '.page-recent .entry .userpic',
            '.page-day .entry .userpic',
            '.entry .userpic',
            '.comment .userpic'
            )
        {
            like( $rules->{$selector} // '',
                qr/margin-top:\s*0;/,
                "modular: $selector no longer overlaps the header on mobile" );
        }
    }

    $ctx->[S2::PROPS]->{sidebar_width} = '12em';
    check_mobile_breakpoint( $ctx, '36em', "$layout with custom sidebar width" );
    $ctx->[S2::PROPS]->{medium_breakpoint_width} = '38em';
    check_mobile_breakpoint( $ctx, '38em', "$layout with explicit medium breakpoint" );
}

done_testing;
