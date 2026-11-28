# t/s2-mobile-lefty-librariansdream.t
#
# Test the narrow-screen stylesheets for Lefty and Librarian's Dream.
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
S2::set_domain('test-mobile-lefty-librariansdream');

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

sub mobile_rules {
    my ( $layout_id, $width, @user_layers ) = @_;
    my $ctx   = S2::make_context( 1, $layout_id, @user_layers );
    my $query = S2::run_function( $ctx, 'generate_small_media_query()' );
    is( $query, "only screen and (max-width: $width)", "Core2 uses a $width mobile breakpoint" );

    my $css = '';
    local $S2::pout   = sub { $css .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $ctx, 'print_stylesheet()' );
    like(
        $css,
        qr/\@media only screen and \(min-width: \Q$width\E\)/,
        'the layout switches to columns at the same breakpoint'
    );

    my %rules;
    while ( $css =~ /\@media \Q$query\E\s*\{((?:[^{}]|\{[^{}]*\})*)\}/g ) {
        my $mobile = $1;
        while ( $mobile =~ /([^{}]+)\{([^{}]*)\}/g ) {
            my ( $selectors, $declarations ) = ( $1, $2 );
            $rules{$_} .= $declarations for split /\s*,\s*/, $selectors =~ s/^\s+|\s+$//gr;
        }
    }
    return \%rules;
}

sub check_mobile_rules {
    my ($rules) = @_;
    like( $rules->{'#canvas'} // '', qr/\bmargin-inline:\s*0;/,    'no configurable page margins' );
    like( $rules->{'#canvas'} // '', qr/\bpadding-inline:\s*8px;/, 'compact fixed page gutters' );
    like( $rules->{'.comment-wrapper'} // '',
        qr/\bmin-width:\s*0;/, 'deeply indented comments can shrink to the available width' );
    like(
        $rules->{'#content .module'} // '',
        qr/\bmax-width:\s*100%;/,
        'fixed-width modules fit their column'
    );
    like(
        $rules->{'#content .module'} // '',
        qr/\bbox-sizing:\s*border-box;/,
        'module width includes its padding and border'
    );

    for my $kind (qw(entry comment module)) {
        my $body = $rules->{".$kind-content"} // '';
        like( $body, qr/\boverflow-x:\s*auto;/,       "$kind text scrolls independently" );
        like( $body, qr/\bmax-width:\s*100%;/,        "$kind text fits its column" );
        like( $body, qr/\bbox-sizing:\s*border-box;/, "$kind text width includes its padding" );
    }

    for my $kind (qw(entry comment)) {
        like(
            $rules->{".$kind-title"} // '',
            qr/\boverflow-wrap:\s*break-word;/,
            "long $kind subjects wrap"
        );
        like( $rules->{".$kind-content"} // '',
            qr/\bclear:\s*both;/, "$kind text scrolls below either userpic float" );
        unlike( $rules->{".$kind .contents > .inner"} // '',
            qr/\boverflow-x:/, "$kind userpic wrapper does not scroll" );
    }
}

sub check_custom_breakpoints {
    my ($layout_id) = @_;
    for my $case ( [ 4, '36em' ], [ 5, '54em' ], [ 6, '30em' ] ) {
        my ( $user_id, $width ) = @$case;
        my $rules = mobile_rules( $layout_id, $width, $user_id );
        like( $rules->{'#canvas'} // '',
            qr/\bmargin-inline:\s*0;/, "fixed gutters apply at the customized $width breakpoint" );
    }
}

load_layer( 1, 'core', read_style('core2.s2') );
my $base = read_style('core2base/layout.s2');
load_layer( 2, 'layout', $base . read_style('lefty/layout.s2') );
load_layer( 3, 'layout', $base . read_style('librariansdream/layout.s2') );
load_layer( 4, 'user',   'layerinfo type = "user"; set sidebar_width = "12em";' );
load_layer( 5, 'user',   'layerinfo type = "user"; set sidebar_width = "18em";' );
load_layer( 6, 'user',
    'layerinfo type = "user"; set sidebar_width = "18em"; set medium_breakpoint_width = "30em";' );

subtest 'Lefty' => sub {
    my $rules = mobile_rules( 2, '45em' );
    check_mobile_rules($rules);
    check_custom_breakpoints(2);
    for my $kind (qw(entry comment)) {
        like( $rules->{".has-userpic .$kind .header"} // '',
            qr/\bmargin-inline:\s*0;/, "$kind header no longer reserves space for its userpic" );
        like( $rules->{".has-userpic .$kind .userpic"} // '',
            qr/\bmargin-top:\s*0;/, "$kind userpic no longer overlaps its header" );
    }
};

subtest "Librarian's Dream" => sub {
    my $rules = mobile_rules( 3, '45em' );
    check_mobile_rules($rules);
    check_custom_breakpoints(3);
    like( $rules->{'#content .module'} // '',
        qr/\bmargin-inline:\s*0;/, 'modules can use their full width without horizontal margins' );
    for my $kind (qw(entry comment)) {
        like( $rules->{".$kind"} // '', qr/\bmargin-left:\s*0;/, "$kind uses the full column" );
        like( $rules->{".$kind-title"} // '',
            qr/\bmargin-left:\s*0;/, "$kind title stays within its header" );
        like( $rules->{".$kind .userpic"} // '',
            qr/\bmargin-top:\s*0;/, "$kind userpic no longer overlaps its header" );
    }
    for my $selector ( '.entry ul.icon-links', '.comment .icon-links' ) {
        my $links = $rules->{$selector} // '';
        like( $links, qr/\bposition:\s*static;/, "$selector stays in the footer flow" );
        like( $links, qr/\bwidth:\s*auto;/, "$selector is not constrained to the old rail width" );
        like( $rules->{"$selector li"} // '',
            qr/\bdisplay:\s*inline;/, "$selector actions appear side by side" );
    }
};

done_testing;
