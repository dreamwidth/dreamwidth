# t/s2-mobile-venture.t
#
# Test Venture's narrow-screen CSS and preserve its desktop stylesheet.
# Venture ships as a standalone Core2 layout. A prepended Core2 Base layer
# compiles, but its stylesheet method takes precedence in the same layer.
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

sub read_style {
    my ($file) = @_;
    open my $source, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    local $/;
    return <$source>;
}

my $compiler = S2::Compiler->new( {} );
S2::set_domain('test-mobile-venture');

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

sub stylesheet {
    my $ctx = S2::make_context( 1, 2, @_ );
    $ctx->[S2::PROPS]->{STYLES_IMGDIR} = 'https://journal.example/img/styles';
    $ctx->[S2::SCRATCH] = {};
    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    my $page = { _type => 'Page' };
    S2::run_code( $ctx, 'prop_init()' );
    S2::Builtin::LJ::start_css($ctx);
    S2::run_code( $ctx, 'Page::print_contextual_stylesheet()', $page );
    S2::run_code( $ctx, 'Page::print_default_stylesheet()',    $page );
    S2::run_code( $ctx, 'print_stylesheet()' );
    S2::run_code( $ctx, 'Page::print_theme_stylesheet()',      $page );
    return $ctx->[S2::SCRATCH]->{_start_css_buffer};
}

sub extract_narrow_rules {
    my ( $css, $breakpoint ) = @_;
    my $query = qr{
        ^\@media\ only\ screen\ and\ \(max-width:\ \Q$breakpoint\E\)\s*\{
            ((?:[^{}]*\{[^{}]*\})*)
        \s*\}\n
    }mx;
    my @narrow_blocks = $$css =~ /$query/g;
    $$css =~ s/$query//g;
    my %rules;
    for my $narrow (@narrow_blocks) {
        while ( $narrow =~ /\s*([^{}]+?)\s*\{([^{}]+)\}/g ) {
            my ( $selectors, $declarations ) = ( $1, $2 );
            $rules{$_} .= $declarations for split /\s*,\s*/, $selectors;
        }
    }
    return \%rules;
}

load_style_layer( 1, 'core', read_style('core2.s2') );
my $venture = read_style('venture/layout.s2');
load_style_layer( 2, 'layout', $venture );

my %desktop_sha = (
    'layout defaults'     => 'c0076e6cba871c2fc4fd7ac24ddc49e505acd97c57196496e1e1bc7518c1fe87',
    'venture/radiantaqua' => '44647800600e869b647088abaeff6081981d7e9d66dad8618fa165fb3b1595d6',
);
my %themes = ( 'layout defaults' => [] );
my $id     = 2;
my $layers = read_style('venture/themes.s2');
while ( $layers =~ /^#NEWLAYER: (venture\/[^\n]+)\n(.*?)(?=^#NEWLAYER:|\z)/msg ) {
    load_style_layer( ++$id, 'theme', $2 );
    $themes{$1} = [$id];
}
is_deeply(
    [ sort keys %themes ],
    [ sort keys %desktop_sha ],
    'baseline covers every Venture theme'
);

for my $theme ( sort keys %themes ) {
    my $css   = stylesheet( @{ $themes{$theme} } );
    my $rules = extract_narrow_rules( \$css, '54em' );
    is( sha256_hex($css), $desktop_sha{$theme}, "$theme desktop CSS is unchanged" );
    like( $css, qr/\@media only screen and \(min-width: 54em\)/,
        "$theme retains its medium query" );
    ok( exists $rules->{'#content'}, "$theme has a 54em narrow query" );
}

my $css   = stylesheet();
my $rules = extract_narrow_rules( \$css, '54em' );
like( $rules->{'#canvas'}  // '', qr/\bmargin:\s*0;/,    'no extra canvas margins' );
like( $rules->{'#content'} // '', qr/\bpadding:\s*8px;/, 'fixed narrow content gutters' );
like( $rules->{'.column-right #content'} // '',
    qr/min-width:\s*0;/, 'sidebar width no longer sets a page minimum' );

for my $kind (qw(entry comment)) {
    for my $selector ( ".$kind .header", ".$kind .$kind-title" ) {
        like( $rules->{$selector} // '', qr/overflow-wrap:\s*anywhere;/, "$selector wraps" );
    }
    like(
        $rules->{".$kind .header > .inner"} // '',
        qr/display:\s*flow-root;/,
        "$kind header contains its floated icon"
    );
    my $icon = $rules->{".$kind .userpic"} // '';
    like( $icon, qr/clear:\s*both;/,     "$kind icon starts below other floats" );
    like( $icon, qr/\bmargin:\s*\.5em;/, "$kind icon does not overlap the subject" );
}

like( $rules->{'.comment-wrapper'} // '', qr/min-width:\s*0;/, 'comment wrappers can shrink' );
like( $rules->{'.comment-depth-10 .dwexpcomment'} // '',
    qr/min-width:\s*0;/, 'deep comment wrapper can shrink' );
like(
    $rules->{'.comment-thread > .dwexpcomment'} // '',
    qr/margin-left:\s*min\(.*80px\)\s*!important;/,
    'legacy comment indentation is capped'
);
like( $rules->{'#content .module'} // '', qr/max-width:\s*100%;/, 'modules fit the viewport' );
like( $rules->{'#content .module'} // '',
    qr/box-sizing:\s*border-box;/, 'module width includes padding and borders' );
like( $rules->{'.one-column #content .module'} // '',
    qr/width:\s*auto;/, 'one-column modules are not squeezed into a row' );

for my $selector ( '.entry-content', '.comment-content', '#canvas .module-content' ) {
    my $content = $rules->{$selector} // '';
    like( $content, qr/overflow-x:\s*auto;/,       "$selector scrolls locally" );
    like( $content, qr/max-width:\s*100%;/,        "$selector fits its panel" );
    like( $content, qr/box-sizing:\s*border-box;/, "$selector width includes padding and borders" );
}

for my $kind (qw(entry comment module)) {
    my $image = $rules->{".$kind-content img"} // '';
    like( $image, qr/max-width:\s*100%;/, "$kind images fit their panels" );
    like( $image, qr/height:\s*auto;/,    "$kind images preserve their aspect ratio" );
}

load_style_layer( ++$id, 'user',
'layerinfo type = "user"; set sidebar_width = "12em"; set comment_indent_style = "responsive"; set userpics_position = "left";'
);
$css   = stylesheet($id);
$rules = extract_narrow_rules( \$css, '36em' );
like( $rules->{'#content'} // '',
    qr/\bpadding:\s*8px;/, 'narrow query follows custom sidebar width' );
like(
    $css,
    qr/\@media only screen and \(min-width: 36em\)/,
    'medium query follows the same breakpoint'
);
ok( !exists $rules->{'.comment-thread > .dwexpcomment'}, 'leaves responsive indentation alone' );
like( $rules->{'.entry .metatime_wrapper'} // '',
    qr/left:\s*auto;/, 'left-side userpic setting does not offset the date out of the header' );

ok( load_style_layer( ++$id, 'layout', read_style('core2base/layout.s2') . $venture ),
    'Venture also compiles with Core2 Base prepended' );

done_testing;
