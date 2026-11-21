#!/usr/bin/perl
# t/contextual-hover-resources.t
#
# Checks the stylesheets delivered for contextual menus and icon dialogs.
#
# Authors:
#      saphid <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Talk;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $smoothness = qr/jquery\.ui\.theme\.smoothness\.css/;
my $contextual = qr/jquery\.contextualhover\.css/;

test_psgi $app, sub {
    my $request = shift;
    for my $skin ( 'lynx', 'gradation-horizontal' ) {
        subtest "$skin contextual menu" => sub {
            my $response = $request->( GET "/manage/settings/?cat=display&skin=$skin" );
            is( $response->code, 200, 'settings page is available' );
            my $styles = join "\n", $response->content =~ /(<link\b[^>]*rel="stylesheet"[^>]*>)/g;
            like( $styles, $contextual, 'ships the contextual menu stylesheet' );
            unlike( $styles, $smoothness, 'does not ship Smoothness for the menu' );
        };
    }
};

{
    local @LJ::NEEDED_RES;
    local %LJ::NEEDED_RES;
    local $LJ::ACTIVE_RES_GROUP = 'jquery';

    LJ::Talk::init_s2journal_js();
    my $head = LJ::res_includes( nojs => 1, no_scripttags => 1 );
    unlike( $head, $smoothness, 'the shared journal resources do not include Smoothness' );
}

{
    local @LJ::NEEDED_RES;
    local %LJ::NEEDED_RES;
    local $LJ::ACTIVE_RES_GROUP = 'jquery';

    LJ::Talk::init_iconbrowser_js();
    my $head = LJ::res_includes( nojs => 1, no_scripttags => 1 );
    like( $head, $smoothness, 'the legacy icon dialog still gets its theme' );
}

done_testing;
