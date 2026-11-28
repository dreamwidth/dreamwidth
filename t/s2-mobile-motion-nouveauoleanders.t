# t/s2-mobile-motion-nouveauoleanders.t
#
# Check mobile widths and overflow behavior in Motion and Nouveau Oleanders CSS.
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
    open my $style, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$style>;
}

sub stylesheet {
    my ( $layout, $property, $value ) = @_;
    S2::set_domain( 'test-mobile-' . $layout . '-' . ( $property // 'default' ) );
    my $compiler = S2::Compiler->new( {} );
    my @layers   = (
        [ core   => read_style('core2.s2') ],
        [ layout => read_style('core2base/layout.s2') . read_style("$layout/layout.s2") ],
    );
    push @layers, [ theme => qq{layerinfo "type" = "theme"; set $property = "$value";} ]
        if defined $property;
    my $id = 0;
    for my $layer (@layers) {
        my ( $type, $source ) = @$layer;
        my $compiled;
        $compiler->compile_source(
            {
                type           => $type,
                source         => \$source,
                output         => \$compiled,
                layerid        => ++$id,
                builtinPackage => 'S2::Builtin::LJ',
            }
        );
        S2::load_layer( $id, $compiled, 0 );
    }

    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    my $ctx = S2::make_context( 1 .. $id );
    $ctx->[S2::SCRATCH] = {};
    S2::Builtin::LJ::start_css($ctx);
    S2::run_code( $ctx, 'print_stylesheet()' );
    S2::Builtin::LJ::end_css($ctx);
    return $css;
}

sub mobile_rules {
    my ( $css, $breakpoint ) = @_;
    my $query = "\@media only screen and (not (min-width: $breakpoint))";
    my ($mobile) = $css =~ /\Q$query\E\s*\{((?:[^{}]*\{[^{}]*\})*)\s*\}/;
    my %rules;
    while ( ( $mobile // '' ) =~ /\s*([^{}]+?)\s*\{([^{}]+)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        $rules{$_} .= $declarations for split /\s*,\s*/, $selectors;
    }
    return \%rules;
}

sub check_breakpoint {
    my ( $css, $breakpoint ) = @_;
    my $rules = mobile_rules( $css, $breakpoint );
    ok( exists $rules->{'#canvas'}, "mobile rules apply strictly below $breakpoint" );
    like(
        $css,
        qr/\@media only screen and \(min-width: \Q$breakpoint\E\)/,
        "medium rules start at $breakpoint"
    );
    return $rules;
}

for my $layout (qw(motion nouveauoleanders)) {
    subtest $layout => sub {
        my $breakpoint = $layout eq 'motion' ? '60em' : '45em';
        my $rules      = check_breakpoint( stylesheet($layout), $breakpoint );
        check_breakpoint( stylesheet( $layout, 'sidebar_width',           '12em' ),  '36em' );
        check_breakpoint( stylesheet( $layout, 'medium_breakpoint_width', '600px' ), '600px' );

        like( $rules->{'#canvas'} // '', qr/margin:\s*0;/,      'ignores configured page margins' );
        like( $rules->{'#canvas'} // '', qr/padding:\s*0 8px;/, 'uses compact fixed page gutters' );
        like( $rules->{'.comment-wrapper'} // '',
            qr/min-width:\s*0;/, 'deeply indented comments can shrink' );

        for my $kind (qw(entry comment module)) {
            my $content = $rules->{".$kind-content"} // '';
            like( $content, qr/overflow-x:\s*auto;/, 'scrolls wide ' . $kind . ' content locally' );
            like( $content, qr/max-width:\s*100%;/,  "$kind content fits its container" );
            like( $content, qr/box-sizing:\s*border-box;/, "$kind content width includes padding" );
            if ( $kind ne 'module' ) {
                like( $content, qr/clear:\s*both;/, "$kind body can use full width below userpic" );
                like(
                    $rules->{".$kind .header"} // '',
                    qr/overflow-wrap:\s*break-word;/,
                    "long $kind subjects wrap"
                );
                unlike( $rules->{".$kind .contents"} // '',
                    qr/overflow/, "$kind userpic wrapper is not a scroll container" );
            }
        }

        if ( $layout eq 'motion' ) {
            my $icon = $rules->{'.icons-container .icon'} // '';
            like( $icon, qr/min-width:\s*0;/,    'icon cards have no minimum width' );
            like( $icon, qr/max-width:\s*100%;/, 'icon cards fit the gallery' );
            for my $column (qw(secondary tertiary)) {
                like( $rules->{"#$column .module"} // '',
                    qr/width:\s*auto;/, "$column modules give up their fixed width" );
            }
        }
        else {
            like(
                $rules->{'#primary > .inner:first-child'} // '',
                qr/padding:\s*1em 0;/,
                'main column has no wide side padding'
            );
            for my $side (qw(odd even)) {
                like( $rules->{".entry-wrapper-$side .contents .entry-poster"} // '',
                    qr/margin-inline:\s*0;/, "$side entry poster stays within the content box" );
                like( $rules->{".comment-wrapper-$side .header"} // '',
                    qr/padding-inline:\s*0;/, "$side comment header drops its extra padding" );
                like( $rules->{".comment-wrapper-$side .contents .userpic"} // '',
                    qr/margin-top:\s*0;/, "$side comment userpic no longer overlaps its date" );
            }
        }
    };
}

done_testing;
