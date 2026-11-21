#!/usr/bin/perl
#
# t/shop-index.t
#
# Test the shop landing page template and shop category panel contrast across skins.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
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

use DW::Request;
use DW::Request::Standard;
use DW::Template;
use HTTP::Request;

sub _parse_color {
    my ($raw) = @_;
    return undef unless defined $raw;

    my $val = lc $raw;
    $val =~ s/!important//g;
    $val =~ s/^\s+|\s+$//g;

    return [ 255, 255, 255 ] if $val eq 'white';
    return [ 0,   0,   0 ]   if $val eq 'black';

    if ( $val =~ /#([0-9a-f]{6})\b/ ) {
        return [ map { hex($_) } ( $1 =~ /../g ) ];
    }
    if ( $val =~ /#([0-9a-f]{3})\b/ ) {
        return [ map { hex( $_ . $_ ) } split //, $1 ];
    }
    if ( $val =~ /rgb\(\s*([0-9.]+)%\s*,\s*([0-9.]+)%\s*,\s*([0-9.]+)%\s*\)/ ) {
        return [ map { $_ * 255 / 100 } ( $1, $2, $3 ) ];
    }
    if ( $val =~ /rgb\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)/ ) {
        return [ $1 + 0, $2 + 0, $3 + 0 ];
    }
    return undef;
}

sub _relative_luminance {
    my ($rgb) = @_;
    my @lin = map {
        my $c = $_ / 255;
        $c <= 0.04045 ? ( $c / 12.92 ) : ( ( ( $c + 0.055 ) / 1.055 )**2.4 );
    } @$rgb;
    return 0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2];
}

sub _contrast_ratio {
    my ( $fg, $bg ) = @_;
    my $l1 = _relative_luminance($fg);
    my $l2 = _relative_luminance($bg);
    my ( $hi, $lo ) = $l1 >= $l2 ? ( $l1, $l2 ) : ( $l2, $l1 );
    return ( $hi + 0.05 ) / ( $lo + 0.05 );
}

sub _parse_top_level_css {
    my ($css) = @_;
    $css =~ s{/\*.*?\*/}{}gs;

    my @rules;
    my $len   = length $css;
    my $pos   = 0;
    my $order = 0;

    while ( $pos < $len ) {
        $pos++ while $pos < $len && substr( $css, $pos, 1 ) =~ /\s/;
        last if $pos >= $len;

        if ( substr( $css, $pos, 1 ) eq '@' ) {
            while ( $pos < $len ) {
                my $ch = substr( $css, $pos++, 1 );
                last if $ch eq ';';
                if ( $ch eq '{' ) {
                    my $depth = 1;
                    while ( $pos < $len && $depth > 0 ) {
                        my $inner = substr( $css, $pos++, 1 );
                        $depth++ if $inner eq '{';
                        $depth-- if $inner eq '}';
                    }
                    last;
                }
            }
            next;
        }

        my $brace = index( $css, '{', $pos );
        last if $brace < 0;
        my $sel_text = substr( $css, $pos, $brace - $pos );
        $pos = $brace + 1;

        my $depth      = 1;
        my $body_start = $pos;
        while ( $pos < $len && $depth > 0 ) {
            my $ch = substr( $css, $pos++, 1 );
            $depth++ if $ch eq '{';
            $depth-- if $ch eq '}';
        }
        my $body = substr( $css, $body_start, $pos - $body_start - 1 );

        my %decls;
        for my $decl ( split /;/, $body ) {
            next unless $decl =~ /^\s*([a-z-]+)\s*:\s*(.+?)\s*$/i;
            $decls{ lc $1 } = $2;
        }
        next unless %decls;

        for my $sel ( split /,/, $sel_text ) {
            $sel =~ s/^\s+|\s+$//g;
            $sel =~ s/\s+/ /g;
            next unless length $sel;
            push @rules, { selector => $sel, decls => \%decls, order => ++$order };
        }
    }

    return \@rules;
}

sub _resolve_prop {
    my ( $rules, $matches, @props ) = @_;
    my $best;
    for my $rule (@$rules) {
        my $spec = $matches->{ $rule->{selector} };
        next unless defined $spec;
        for my $prop (@props) {
            next unless exists $rule->{decls}{$prop};
            if (  !$best
                || $spec > $best->{spec}
                || ( $spec == $best->{spec} && $rule->{order} > $best->{order} ) )
            {
                $best = {
                    spec  => $spec,
                    order => $rule->{order},
                    value => $rule->{decls}{$prop},
                };
            }
        }
    }
    return $best ? $best->{value} : undef;
}

sub _compile_skin_css {
    my ($skin_path) = @_;
    my @cmd = (
        'sass',             '--quiet',
        '--style=expanded', '--no-source-map',
        "--load-path=$ENV{LJHOME}/htdocs/scss",
    );
    if ( -d "$ENV{LJHOME}/ext/dw-nonfree/htdocs/scss" ) {
        push @cmd, "--load-path=$ENV{LJHOME}/ext/dw-nonfree/htdocs/scss";
    }
    push @cmd, $skin_path;

    open my $fh, '-|', @cmd or die "Failed to run sass on $skin_path: $!";
    local $/;
    my $css = <$fh>;
    close $fh;
    die "sass failed for $skin_path (exit $?)" if $?;
    return $css;
}

subtest 'shop index template renders responsive panels and account branches' => sub {
    DW::Request->reset;
    DW::Request::Standard->new( HTTP::Request->new( GET => 'http://www.dw.test/shop' ) );

    my %all_enabled = ( points => 1, rename => 1, icons => 1 );

    my $anon_html = DW::Template->template_string(
        'shop/index.tt',
        {
            cart_display => '<div id="shop-status-bar"></div>',
            shop_config  => \%all_enabled,
        }
    );
    my @anon_panels = ( $anon_html =~ /<div class="panel shop-category-panel">/g );
    is( scalar @anon_panels, 4, 'anonymous view renders four shop-category panels' );
    like( $anon_html, qr{<div class="row">}, 'uses Foundation row' );
    like( $anon_html, qr{<div class="small-12 medium-6 columns">}, 'uses responsive columns' );
    like( $anon_html, qr{/account\?for=gift"}, 'anonymous can gift paid account' );
    like( $anon_html, qr{/account\?for=new"},  'anonymous can buy new account' );
    like( $anon_html, qr{/randomgift"},        'anonymous can buy random gift' );
    like( $anon_html, qr{/icons\?for=gift"},   'anonymous can gift icons' );
    unlike( $anon_html, qr{\?for=self"}, 'anonymous has no self-purchase links' );

    my $personal_html = DW::Template->template_string(
        'shop/index.tt',
        {
            cart_display => '<div id="shop-status-bar"></div>',
            shop_config  => \%all_enabled,
            remote       => {
                is_personal => 1,
                is_perm     => 0,
                ljuser_display =>
                    '<span class="ljuser"><a href="/profile"><b>testuser</b></a></span>',
            },
        }
    );
    like( $personal_html, qr{/account\?for=self"},   'personal user gets paid account self link' );
    like( $personal_html, qr{/gifts\?type=account"}, 'personal user gets circle gift link' );
    like( $personal_html, qr{/points\?for=self"},    'personal user gets points self link' );
    like( $personal_html, qr{/renames\?for=self"},   'personal user gets renames self link' );
    like( $personal_html, qr{/icons\?for=self"},     'personal user gets icons self link' );
    like( $personal_html, qr{testuser},              'personal user display is included' );

    my $perm_html = DW::Template->template_string(
        'shop/index.tt',
        {
            cart_display => '<div id="shop-status-bar"></div>',
            shop_config  => \%all_enabled,
            remote       => {
                is_personal => 1,
                is_perm     => 1,
                ljuser_display =>
                    '<span class="ljuser"><a href="/profile"><b>permuser</b></a></span>',
            },
        }
    );
    unlike( $perm_html, qr{/account\?for=self"},
        'permanent user cannot buy paid account for self' );
    like( $perm_html, qr{/points\?for=self"},  'permanent user can still buy points for self' );
    like( $perm_html, qr{/renames\?for=self"}, 'permanent user can still buy renames for self' );
    like( $perm_html, qr{/icons\?for=self"},   'permanent user can still buy icons for self' );

    my $disabled_html = DW::Template->template_string(
        'shop/index.tt',
        {
            cart_display => '<div id="shop-status-bar"></div>',
            shop_config  => { points => 0, rename => 0, icons => 0 },
            remote       => {
                is_personal => 1,
                is_perm     => 0,
                ljuser_display =>
                    '<span class="ljuser"><a href="/profile"><b>testuser</b></a></span>',
            },
        }
    );
    unlike( $disabled_html, qr{/points\?for=},  'unavailable points omits purchase links' );
    unlike( $disabled_html, qr{/renames\?for=}, 'unavailable renames omits purchase links' );
    unlike( $disabled_html, qr{/icons\?for=},   'unavailable icons omits purchase links' );
};

subtest 'shop category panel links meet WCAG 2.2 AA contrast in all skins' => sub {
    my @skins = (
        [ 'celerity', "$ENV{LJHOME}/htdocs/scss/skins/celerity.scss" ],
        [
            'gradation-vertical',
            "$ENV{LJHOME}/htdocs/scss/skins/gradation/gradation-vertical.scss"
        ],
        [
            'gradation-horizontal',
            "$ENV{LJHOME}/htdocs/scss/skins/gradation/gradation-horizontal.scss"
        ],
    );
    for my $tropo (
        [ 'tropo-red',    "$ENV{LJHOME}/ext/dw-nonfree/htdocs/scss/skins/tropo/tropo-red.scss" ],
        [ 'tropo-purple', "$ENV{LJHOME}/ext/dw-nonfree/htdocs/scss/skins/tropo/tropo-purple.scss" ],
        )
    {
        push @skins, $tropo if -f $tropo->[1];
    }

    my %panel_match = (
        '.panel'                     => 10,
        '.shop-category-panel'       => 10,
        '.panel.shop-category-panel' => 20,
    );

    my %base_link = (
        'a'                            => 1,
        '.panel a'                     => 11,
        '.shop-category-panel a'       => 11,
        '.panel.shop-category-panel a' => 21,
    );

    my %visited_link = (
        %base_link,
        'a:visited'                            => 11,
        '.panel a:visited'                     => 21,
        '.shop-category-panel a:visited'       => 21,
        '.panel.shop-category-panel a:visited' => 31,
    );

    my %hover_link = (
        %visited_link,
        'a:hover'                            => 11,
        '.panel a:hover'                     => 21,
        '.shop-category-panel a:hover'       => 21,
        '.panel.shop-category-panel a:hover' => 31,
    );

    my %focus_link = (
        %visited_link,
        'a:hover'                            => 11,
        'a:focus'                            => 11,
        '.panel a:focus'                     => 21,
        '.shop-category-panel a:focus'       => 21,
        '.panel.shop-category-panel a:focus' => 31,
    );

    my %active_link = (
        %visited_link,
        'a:active'                            => 11,
        '.panel a:active'                     => 21,
        '.shop-category-panel a:active'       => 21,
        '.panel.shop-category-panel a:active' => 31,
    );

    my %ljuser_base = (
        %base_link,
        '.ljuser a'                            => 11,
        '.panel .ljuser a'                     => 21,
        '.shop-category-panel .ljuser a'       => 21,
        '.panel.shop-category-panel .ljuser a' => 31,
    );

    my %ljuser_visited = (
        %ljuser_base,
        'a:visited'                                    => 11,
        '.ljuser a:visited'                            => 21,
        '.panel.shop-category-panel a:visited'         => 31,
        '.panel.shop-category-panel .ljuser a:visited' => 41,
    );

    my %ljuser_hover = (
        %ljuser_visited,
        'a:hover'                                    => 11,
        '.ljuser a:hover'                            => 21,
        '.panel.shop-category-panel a:hover'         => 31,
        '.panel.shop-category-panel .ljuser a:hover' => 41,
    );

    my %ljuser_focus = (
        %ljuser_visited,
        'a:focus'                                    => 11,
        '.ljuser a:focus'                            => 21,
        '.panel.shop-category-panel a:focus'         => 31,
        '.panel.shop-category-panel .ljuser a:focus' => 41,
    );

    my @states = (
        [ 'normal link',    \%base_link ],
        [ 'visited link',   \%visited_link ],
        [ 'hover link',     \%hover_link ],
        [ 'focus link',     \%focus_link ],
        [ 'active link',    \%active_link ],
        [ 'ljuser normal',  \%ljuser_base ],
        [ 'ljuser visited', \%ljuser_visited ],
        [ 'ljuser hover',   \%ljuser_hover ],
        [ 'ljuser focus',   \%ljuser_focus ],
    );

    for my $entry (@skins) {
        my ( $name, $path ) = @$entry;
        my $css   = _compile_skin_css($path);
        my $rules = _parse_top_level_css($css);

        my $bg_raw = _resolve_prop( $rules, \%panel_match, 'background-color', 'background' );
        my $bg_rgb = _parse_color($bg_raw);
        ok( $bg_rgb,
            "$name resolves a shop panel background color (" . ( $bg_raw // 'undef' ) . ')' );
        next unless $bg_rgb;

        for my $state (@states) {
            my ( $label, $match ) = @$state;
            my $fg_raw = _resolve_prop( $rules, $match, 'color' );
            my $fg_rgb = _parse_color($fg_raw);
            ok( $fg_rgb,
                "$name $label resolves a foreground color (" . ( $fg_raw // 'undef' ) . ')' );
            next unless $fg_rgb;

            my $ratio = _contrast_ratio( $fg_rgb, $bg_rgb );
            cmp_ok(
                $ratio, '>=', 4.5,
                sprintf(
                    '%s %s (%s on %s) meets 4.5:1 contrast (got %.2f:1)',
                    $name, $label, $fg_raw, $bg_raw, $ratio
                )
            );
        }

        my $focus_outline = _resolve_prop( $rules, \%focus_link, 'outline' );
        ok(
            defined $focus_outline
                && $focus_outline !~ /^(?:0|none)\b/i
                && $focus_outline =~ /\b[1-9]\d*px\b/i,
            "$name focus link keeps a visible outline (" . ( $focus_outline // 'undef' ) . ')'
        );
    }
};

done_testing();
