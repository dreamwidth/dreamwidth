# t/s2-mobile-trifecta-wideopen.t
#
# Test narrow-screen styles for Trifecta and Wide Open.
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

use Digest::SHA qw(sha256_hex);
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use S2;
use S2::Compiler;

my $compiler = S2::Compiler->new( {} );
my $layer_id = 0;
S2::set_domain('test-mobile-trifecta-wideopen');

sub read_style {
    my ($file) = @_;
    open my $source, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$source>;
}

sub load_style {
    my ( $type, $source ) = @_;
    my $compiled;
    $compiler->compile_source(
        {
            type           => $type,
            source         => \$source,
            output         => \$compiled,
            layerid        => ++$layer_id,
            builtinPackage => 'S2::Builtin::LJ',
        }
    );
    S2::load_layer( $layer_id, $compiled, 0 );
    return $layer_id;
}

sub stylesheet {
    my (@layers) = @_;
    my $ctx      = S2::make_context(@layers);
    my $css      = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'print_stylesheet()' );
    $css =~ s{/\*.*?\*/}{}gs;
    return $css;
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

my %desktop_fingerprint = (
    'trifecta/bluelove'       => '827bf67855f217481bea1295c2b145f45289810609f0a202fa2cbff622cb982c',
    'trifecta/carriedaway'    => '90b69751de7936145c786884e08824d74b01ecda67221baca0c315ce50a6edfa',
    'trifecta/coffeeandcream' => '2cf1e561138ee8aaf99201c7695556960e1c4355209e5a0e9291941489407e81',
    'trifecta/deepseas'       => '011ffa84b32e3c42d955f4e05236416a9195ed3c6beba76feec9fb4794c9a503',
    'trifecta/handlewithcare' => '50bc3f26d935ac9adf5636beaa76cc9e740c9b6455fabdca2e656f495efdb0ce',
    'trifecta/itsamystery'    => '58397b07b593515b3e841c254aad7d15f7c803f2ef5be245bd05656c460a1e19',
    'trifecta/juice'          => '769589629d8805b76bbf68abcba3147a2400466f3f1f518761c64d79bfefd183',
    'trifecta/morningwalk'    => '4529bda3f44633c9614b67ec1c7ac7194b9ee35b730ba034df25c343c8f24b32',
    'trifecta/mythicalbeast'  => '565f62f6a721bb91d149e1f4eafc5b7277ce0c9abc9bc7050a6423cb60afd515',
    'trifecta/peacefullife'   => 'bb377ef48a99606868daa0b6984c8d0f6b09631ce42430e47c400ec7ffbe0cee',
    'trifecta/purplelove'     => 'a1cfdf22d4808a3e292444086ae8f0add9e34e1df7474f4b7b71a0f7c26cb432',
    'trifecta/sanddune'       => '8f60163c3aa7cbc997f06b218ae5ab55f270051ab4f9d626223994b52a5262b8',
    'trifecta/skinsoft'       => '2307934e55dbcf7c2e5b8e2acc28965bfe6afa579068fba16a89fd38e57c1bce',
    'trifecta/timber'         => '147b7e558c6224366eef831acc23bd3725cb8b13b524180b5575f459a9018c7a',
    'trifecta/youresosweet'   => 'fc571dc6c268b4b2830f9de6e03e9a85cc0d35fc69c7aadde80803b9e62b1011',
    'wideopen/koi'            => '44892019f424bd373b206e9798ad3ce0744fbfd7b342058359c6d8d49ad19603',
);
my $core      = load_style( 'core', read_style('core2.s2') );
my $core2base = read_style('core2base/layout.s2');
my $rules     = qr/((?:[^{}]*\{[^{}]*\})*\s*)/;

for my $layout (qw(trifecta wideopen)) {
    subtest $layout => sub {
        my $layer    = load_style( 'layout', $core2base . read_style("$layout/layout.s2") );
        my $css      = stylesheet( $core, $layer );
        my $width    = $layout eq 'trifecta' ? '45em' : '54em';
        my ($mobile) = $css =~ /\@media only screen and \(max-width: \Q$width\E\)\s*\{$rules\}/;
        ok( defined $mobile, "mobile overrides use Core2's $width breakpoint" );
        like(
            $css,
            qr/\@media only screen and \(min-width: \Q$width\E\)/,
            'the medium rules start at the same boundary'
        );
        $mobile //= '';

        my $canvas = declarations_for( $mobile, '#canvas' );
        like( $canvas, qr/\bmargin-inline:\s*0;/,    'removes configurable canvas margins' );
        like( $canvas, qr/\bpadding-inline:\s*8px;/, 'gives the canvas a single fixed gutter' );
        if ( $layout eq 'wideopen' ) {
            like( declarations_for( $mobile, '#content' ),
                qr/\bmargin-inline:\s*0;/, 'does not add percentage margins to the gutter' );
            like( declarations_for( $mobile, '.page-read .entry' ),
                qr/\bpadding-inline:\s*0;/, 'entry pages also give back the reserved icon column' );
        }

        for my $kind (qw(entry comment)) {
            my $header = declarations_for( $mobile, ".$kind .header" );
            like( $header, qr/\boverflow-wrap:\s*anywhere;/, "$kind header wraps" );
            like(
                declarations_for( $mobile, ".$kind .$kind-title" ),
                qr/\boverflow-wrap:\s*anywhere;/,
                "$kind subject wraps"
            );
            my $userpic = declarations_for( $mobile, ".$kind .userpic" );
            if ( $layout eq 'trifecta' ) {
                like( $header, qr/\bmargin-inline:\s*0;/, "$kind header uses the full width" );
                like( $userpic, qr/\bfloat:\s*none;/, "$kind icon does not float beside content" );
            }
            else {
                like(
                    declarations_for( $mobile, ".$kind" ),
                    qr/\bpadding-inline:\s*0;/,
                    "$kind has no reserved icon column"
                );
                like( $userpic, qr/\bposition:\s*static;/, "$kind icon is in normal flow" );
            }
        }

        like( declarations_for( $mobile, '.comment-wrapper' ),
            qr/\bmin-width:\s*0;/,
            'deeply nested comments can shrink below the Core2 minimum width' );
        my $module = declarations_for( $mobile, '#canvas .module' );
        like( $module, qr/\bmax-width:\s*100%;/, 'modules are capped by their parent width' );
        like( $module, qr/\bbox-sizing:\s*border-box;/, 'module widths include padding' );

        for my $kind (qw(entry comment module)) {
            my $content = declarations_for( $mobile, ".$kind-content" );
            like( $content, qr/\boverflow-x:\s*auto;/, "$kind content scrolls independently" );
            like( $content, qr/\bmax-width:\s*100%;/,  "$kind content is bounded by its parent" );
            like( $content, qr/\bbox-sizing:\s*border-box;/, "$kind width includes its padding" );
            my $image = declarations_for( $mobile, ".$kind-content img" );
            like( $image, qr/\bmax-width:\s*100%;/, "$kind images fit their container" );
            like( $image, qr/\bheight:\s*auto;/,    "$kind images keep their aspect ratio" );
        }

        my $themes = read_style("$layout/themes.s2");
        my @themes;
        while ( $themes =~ /^#NEWLAYER: \Q$layout\E\/(\w+)\n(.*?)(?=^#NEWLAYER:|\z)/msg ) {
            my ( $name, $source ) = ( $1, $2 );
            push @themes, $name;
            my $theme_css = stylesheet( $core, $layer, load_style( 'theme', $source ) );
            $theme_css =~ s/\@media only screen and \(max-width: \Q$width\E\)\s*\{$rules\}//g;
            $theme_css =~ s/\s+/ /g;
            $theme_css =~ s/^ | $//g;
            is(
                sha256_hex($theme_css),
                $desktop_fingerprint{"$layout/$name"},
                "$name: desktop CSS matches the pre-fix stylesheet"
            );
        }
        ok( @themes, 'found the built-in themes' );
    };
}

done_testing;
