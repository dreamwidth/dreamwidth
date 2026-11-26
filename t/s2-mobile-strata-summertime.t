# t/s2-mobile-strata-summertime.t
#
# Test the narrow-screen styles for Strata and Summertime.
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

sub stylesheet {
    my (@ids) = @_;
    my $context = S2::make_context(@ids);
    $context->[S2::PROPS]->{STYLES_IMGDIR} = 'https://example.test/styles';
    $context->[S2::SCRATCH] = {};

    local $S2::pout   = sub { };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $context, 'prop_init()' );
    S2::Builtin::LJ::start_css($context);
    S2::run_code( $context, 'Page::print_contextual_stylesheet()', { _type => 'Page' } );
    S2::run_code( $context, 'Page::print_default_stylesheet()',    { _type => 'Page' } );
    S2::run_code( $context, 'print_stylesheet()' );
    S2::run_code( $context, 'Page::print_theme_stylesheet()', { _type => 'Page' } );
    return $context->[S2::SCRATCH]->{_start_css_buffer};
}

sub mobile_rules {
    my ($css) = @_;
    while ( $$css =~ /\n^\@media ([^\n]+) \{\n(.*?)^\}\n/msg ) {
        my ( $query, $rules, $block ) = ( $1, $2, $& );
        next unless $rules =~ /overflow-x:\s*auto/ && $rules =~ /\.comment-wrapper/;
        $$css =~ s/\Q$block\E//;
        return ( $query, $rules );
    }
    return ( '', '' );
}

sub declarations {
    my ($css) = @_;
    my %rules;
    while ( $css =~ /([^{}]+)\{([^{}]*)\}/g ) {
        my ( $selectors, $declarations ) = ( $1, $2 );
        my %properties = $declarations =~ /([\w-]+):\s*([^;]+?)\s*;/g;
        for my $selector ( split /\s*,\s*/, $selectors ) {
            $selector =~ s/^\s+|\s+$//g;
            $rules{$selector} = { %{ $rules{$selector} // {} }, %properties };
        }
    }
    return \%rules;
}

my %breakpoints    = ( strata => '45em', summertime => '51em' );
my %desktop_sha256 = (
    strata     => '2940499451887f43f22c00e547bb328d81b7bcb78d2743f44f19701bb45074f8',
    summertime => '4aef56c7d3982608f022110ecb2f237b85afc5513897e3418f8279bf9aed30ef',
);

for my $layout (qw(strata summertime)) {
    subtest $layout => sub {
        S2::set_domain("test-mobile-$layout");
        my $compiler = S2::Compiler->new( {} );
        load_layer( $compiler, 1, 'core', read_style('core2.s2') );
        load_layer( $compiler, 2, 'layout',
            read_style('core2base/layout.s2') . read_style("$layout/layout.s2") );

        my $css = stylesheet( 1, 2 );
        like(
            $css,
            qr/^\@media only screen and \(min-width: $breakpoints{$layout}\)/m,
            'Core2 switches to columns at the layout breakpoint'
        );
        my ( $query, $mobile ) = mobile_rules( \$css );
        is(
            $query,
            "only screen and (max-width: $breakpoints{$layout})",
            'mobile rules use the matching Core2 breakpoint'
        );

        my $rules = declarations($mobile);
        is( $rules->{'#canvas'}->{margin},               '0 8px', 'fixed outer gutters' );
        is( $rules->{'.comment-wrapper'}->{'min-width'}, '0',     'nested comments can shrink' );
        is_deeply(
            $rules->{'#content .module'},
            { 'max-width' => '100%', 'box-sizing' => 'border-box' },
            'sidebar modules do not exceed the available width'
        );

        for my $selector ( '.entry .header', '.comment .header', '.entry-title', '.comment-title' )
        {
            is( $rules->{$selector}->{'overflow-wrap'}, 'anywhere', "$selector wraps long words" );
        }

        for my $selector (qw(.entry-content .comment-content .module-content)) {
            my $rule = $rules->{$selector};
            is_deeply(
                [ @$rule{qw(overflow-x max-width box-sizing)} ],
                [ 'auto', '100%', 'border-box' ],
                "$selector scrolls independently instead of widening the page"
            );
            is_deeply(
                $rules->{"$selector img"},
                { 'max-width' => '100%', height => 'auto' },
                "$selector scales large images proportionally"
            );
        }
        is( $rules->{'.comment-content:before'}->{'max-width'},
            '100%', 'the Core2 comment spacer cannot cause scrolling on its own' );
        is( $rules->{'.entry-content'}->{clear}, 'both', 'entry text clears the floated userpic' );

        if ( $layout eq 'strata' ) {
            is( $rules->{body}->{margin}, '0', 'body does not add a second gutter' );
            is( $rules->{'#primary > .inner:first-child'}->{padding},
                '0', 'column spacing does not add a second gutter' );
            is( $rules->{'.entry'}->{'border-width'}, '8px', 'keeps the layered entry border' );
            is( $rules->{'#comments .comment-content'}->{padding},
                '10px', 'keeps padding inside the comment panel' );
            is( $rules->{'.entry .userpic img'}->{margin}, '0', 'no extra entry userpic offset' );
            is( $rules->{'.comment .comment-content'}->{clear},
                'both', 'comment text clears either userpic alignment' );
        }
        else {
            for my $selector ( '#content', '#secondary-container', '#tertiary-container' ) {
                is( $rules->{$selector}->{margin}, '0', "$selector uses the canvas gutter" );
            }
            is( $rules->{'.entry'}->{padding}, '12px', 'keeps padding inside the entry panel' );
            is( $rules->{'.comment-content'}->{clear},
                'both', 'comment text clears either userpic alignment' );
            for my $kind (qw(entry comment)) {
                is_deeply(
                    $rules->{".has-userpic .$kind .header"},
                    { 'margin-left' => '0', 'margin-right' => '0' },
                    "$kind header uses the full panel width with a userpic"
                );
                is( $rules->{".has-userpic .$kind .userpic"}->{'margin-top'},
                    '0', "$kind userpic stays below its header" );
            }
        }

        my @themes =
            read_style("$layout/themes.s2") =~ /^\#NEWLAYER: (\S+)\n(.*?)(?=^\#NEWLAYER:|\z)/msg;
        my $id = 2;
        my @desktop;
        while (@themes) {
            my ( $name, $theme ) = splice @themes, 0, 2;
            load_layer( $compiler, ++$id, 'theme', $theme );
            my $theme_css = stylesheet( 1, 2, $id );
            mobile_rules( \$theme_css );
            push @desktop, "$name\0$theme_css";
        }
        ok( @desktop, 'found built-in themes' );
        is(
            sha256_hex( join "\0", @desktop ),
            $desktop_sha256{$layout},
            'desktop CSS matches the baseline across all built-in themes'
        );
    };
}

done_testing;
