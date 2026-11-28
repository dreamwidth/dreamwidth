#!/usr/bin/perl
#
# t/shop-cart-links.t
#
# Test that support links on the shop cart page point to SITEROOT so they do
# not break when the shop runs on its own subdomain.
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

subtest 'shop cart payment failure links use site.root' => sub {
    local $LJ::SITEROOT = 'https://www.example.org';
    local $LJ::SHOPROOT = 'https://shop.example.org';

    DW::Request->reset;
    my $req = HTTP::Request->new( GET => 'https://shop.example.org/shop/cart' );
    $req->header( Host => 'shop.example.org' );
    DW::Request::Standard->new($req);

    my $dup_html = DW::Template->template_string(
        'shop/cart.tt',
        {
            duplicate   => 1,
            failed      => 0,
            cart_widget => '',
        }
    );
    like(
        $dup_html,
        qr{<a\b[^>]*href=['"]https://www\.example\.org/support/submit['"]},
        'duplicate payment failure links to SITEROOT/support/submit'
    );
    unlike(
        $dup_html,
        qr{href=['"]/support/submit['"]},
        'duplicate payment failure does not use a root-relative support link'
    );

    my $failed_html = DW::Template->template_string(
        'shop/cart.tt',
        {
            duplicate   => 0,
            failed      => 1,
            cart_widget => '',
        }
    );
    like(
        $failed_html,
        qr{<a\b[^>]*href=['"]https://www\.example\.org/support/submit['"]},
        'generic payment failure links to SITEROOT/support/submit'
    );
    unlike(
        $failed_html,
        qr{href=['"]/support/submit['"]},
        'generic payment failure does not use a root-relative support link'
    );
};

done_testing();
