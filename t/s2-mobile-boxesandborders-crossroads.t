# t/s2-mobile-boxesandborders-crossroads.t
#
# Test narrow-screen CSS emitted by Boxes and Borders and Crossroads.
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
S2::set_domain('test-mobile-boxesandborders-crossroads');

sub load_layer {
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

load_layer( 1, 'core', read_style('core2.s2') );
my $base = read_style('core2base/layout.s2');

sub mobile_rules {
    my ($layout_id) = @_;
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( S2::make_context( 1, $layout_id ), 'print_stylesheet()' );

    my ($mobile) =
        $css =~ /\@media only screen and \(max-width: 45em\)\s*\{((?:[^{}]|\{[^{}]*\})*)\}/;
    my %rules;
    while ( ( $mobile // '' ) =~ /([^{}]+)\{([^{}]*)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        $rules{$_} .= $declarations for split /\s*,\s*/, $selectors =~ s/^\s+|\s+$//gr;
    }
    return \%rules;
}

sub contains_wide_content {
    my ( $rules, $selector, $layout ) = @_;
    my $declarations = $rules->{$selector} // '';
    like( $declarations, qr/\boverflow-x:\s*auto;/, "$layout: $selector scrolls independently" );
    like( $declarations, qr/\bmax-width:\s*100%;/,  "$layout: $selector fits its column" );
    like( $declarations, qr/\bbox-sizing:\s*border-box;/, "$layout: $selector counts its padding" );
}

load_layer( 2, 'layout', $base . read_style('boxesandborders/layout.s2') );
my $boxes = mobile_rules(2);
like( $boxes->{'#canvas'} // '',
    qr/\bmargin-inline:\s*0;/, 'Boxes and Borders: no configurable canvas margins' );
like( $boxes->{'#primary > .inner:first-child'} // '',
    qr/\bpadding:\s*8px;/, 'Boxes and Borders: compact fixed padding around the primary column' );
for my $kind (qw(entry comment)) {
    contains_wide_content( $boxes, ".$kind .contents > .inner", 'Boxes and Borders' );
    like(
        $boxes->{".$kind-title"} // '',
        qr/\boverflow-wrap:\s*anywhere;/,
        "Boxes and Borders: long $kind subjects wrap"
    );
}
contains_wide_content( $boxes, '.module-content', 'Boxes and Borders' );

load_layer( 3, 'layout', $base . read_style('crossroads/layout.s2') );
my $crossroads = mobile_rules(3);
like( $crossroads->{'#canvas'} // '',
    qr/\bmargin-inline:\s*0;/, 'Crossroads: no configurable canvas margins' );
like( $crossroads->{'#content'} // '',
    qr/\bmargin:\s*0;/, 'Crossroads: no percentage content margin' );
like( $crossroads->{'#content'} // '',
    qr/\bpadding-inline:\s*8px;/, 'Crossroads: compact fixed padding around the content' );
for my $kind (qw(entry comment)) {
    contains_wide_content( $crossroads, ".$kind-content", 'Crossroads' );
    like( $crossroads->{".$kind .contents .userpic"} // '',
        qr/\bposition:\s*static;/, "Crossroads: $kind icon stays in flow, outside the scrollport" );
}
for my $header ( '.entry .header', '.comment-wrapper .header' ) {
    like( $crossroads->{$header} // '',
        qr/\bmargin-inline:\s*0;/, "Crossroads: $header reserves no horizontal space for an icon" );
}
contains_wide_content( $crossroads, '.module-content', 'Crossroads' );

done_testing;
