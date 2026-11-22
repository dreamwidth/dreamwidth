# t/s2-mobile-paletteable-headsup.t
#
# Test the mobile CSS emitted by Paletteable and Heads Up.
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
S2::set_domain('test-mobile-paletteable-headsup');

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

sub mobile_css {
    my ($layout_id) = @_;
    my $ctx = S2::make_context( 1, $layout_id );
    $ctx->[S2::SCRATCH] = {};
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'prop_init()' );
    S2::run_code( $ctx, 'print_stylesheet()' );

    my ($mobile) =
        $css =~ /\@media only screen and \(max-width: 45em\)\s*\{((?:[^{}]*\{[^{}]*\})*)/;
    return $mobile // '';
}

sub declarations_for {
    my ( $css, $selector ) = @_;
    my %declarations;
    while ( $css =~ /([^{}]+)\{([^{}]*)\}/g ) {
        my ( $selectors, $body ) = ( $1, $2 );
        next unless grep { $_ eq $selector } split /\s*,\s*/, $selectors =~ s/^\s+|\s+$//gr;
        %declarations = ( %declarations, $body =~ /([a-z-]+):\s*([^;]+);/g );
    }
    return \%declarations;
}

load_style_layer( 1, 'core', read_style('core2.s2') );
my $base      = read_style('core2base/layout.s2');
my $layout_id = 1;

for my $layout (qw(paletteable headsup)) {
    load_style_layer( ++$layout_id, 'layout', $base . read_style("$layout/layout.s2") );
    my $css    = mobile_css($layout_id);
    my $canvas = declarations_for( $css, '#canvas' );
    like( $canvas->{'margin-inline'} // '', qr/^\d+px$/, "$layout: fixed mobile page gutters" );
    if ( $layout eq 'headsup' ) {
        is( $canvas->{width}, 'auto',
            "$layout: configured desktop width does not apply on mobile" );
    }

    for my $type (qw(entry comment)) {
        my $header = declarations_for( $css, ".$type .header" );
        is( $header->{'margin-inline'}, '0', "$layout: $type header has room for the subject" );
        is( $header->{'overflow-wrap'}, 'break-word', "$layout: long $type subjects can wrap" );
        my $text = declarations_for( $css, ".$type-content" );
        is( $text->{clear}, 'both', "$layout: $type text scrolls below its floated userpic" );
    }

    for my $type (qw(entry comment module)) {
        my $content = declarations_for( $css, ".$type-content" );
        is( $content->{'overflow-x'}, 'auto',       "$layout: wide $type content can scroll" );
        is( $content->{'max-width'},  '100%',       "$layout: $type content fits its container" );
        is( $content->{'box-sizing'}, 'border-box', "$layout: padding cannot widen $type content" );
    }
}

done_testing;
