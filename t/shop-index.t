#!/usr/bin/perl
#
# t/shop-index.t
#
# Test the shop landing page template.
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
    my @anon_panels = ( $anon_html =~ /<div class="panel">/g );
    is( scalar @anon_panels, 4, 'anonymous view renders four standard Foundation panels' );
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

done_testing();
