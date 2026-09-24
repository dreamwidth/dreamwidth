#!/usr/bin/perl
#
# t/sitescheme-render-all.t
#
# Confirms DW::Template->render_scheme (via render_string's supports_tt
# check) still resolves and renders every selectable scheme after removing
# the tt_runner engine=>'bml' entry and DW::SiteScheme::supports_bml.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::SiteScheme;

plan skip_all => 'render_scheme integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my @schemes = map { $_->{scheme} } DW::SiteScheme->available;
ok( scalar(@schemes), 'fixture: at least one selectable scheme is configured' );

test_psgi $app, sub {
    my $cb = shift;
    for my $scheme (@schemes) {
        my $res = $cb->( GET "/?usescheme=$scheme" );
        is( $res->code, 200, "scheme '$scheme' renders" );
        ok( length( $res->content ) > 0, "scheme '$scheme' produces non-empty output" );
    }
};

done_testing;
