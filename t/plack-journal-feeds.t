#!/usr/bin/perl
#
# t/plack-journal-feeds.t
#
# Journal RSS/Atom Plack characterization for adapter-removal preparation.
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
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use DW::Controller::Journal;
use DW::Request::Plack;

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $entry = $u->t_post_fake_entry(
    subject => 'Adapter feed subject',
    event   => 'Adapter feed body',
);
my $base = 'http://localhost/data';

# This is an HTTP-level controller harness: it supplies the normal Plack request
# object while avoiding vhost policy, which is outside Journal feed rendering.
my $app = sub {
    my ($env) = @_;
    DW::Request->reset;
    my $r = DW::Request::Plack->new($env);
    $r->status(200);
    my $ret = DW::Controller::Journal->render(
        user => $u->user,
        uri  => $r->uri,
        args => $r->query_string,
    );
    $r->status($ret) if defined $ret && !ref $ret && $ret > 0;
    return $ret if ref $ret;
    return $r->res;
};

no warnings 'redefine';
local *DW::Routing::call = sub { return undef };

# Journal.pm uses the users-vhost branch; grant only that fixture capability so
# this test reaches the public feed behavior rather than the separate vhost notice.
local *LJ::get_cap = sub { return $_[1] eq 'userdomain' ? 1 : 0 };

test_psgi $app, sub {
    my $cb = shift;
    for my $feed ( [ rss => qr{<rss\b}i, 'RSS' ], [ atom => qr{<feed\b}i, 'Atom' ], ) {
        my ( $kind, $root, $label ) = @$feed;
        my $res = $cb->( GET "$base/$kind" );
        is( $res->code, 200, "$label journal feed renders through the Plack Journal controller" );
        like(
            $res->header('Content-Type') || '',
            qr{text/xml;\s*charset=utf-8}i,
            "$label response keeps XML UTF-8 content type"
        );
        like( $res->content, $root, "$label response has its feed root" );
        like(
            $res->content,
            qr/Adapter feed subject/,
            "$label response includes public entry content"
        );
        ok( $res->header('Last-Modified'), "$label response supplies feed modification time" );
    }

    my $first         = $cb->( GET "$base/rss" );
    my $last_modified = $first->header('Last-Modified');
    ok( $last_modified, 'RSS baseline has Last-Modified for conditional request' );
    my $conditional = $cb->( GET "$base/rss", 'If-Modified-Since' => $last_modified, );
    is( $conditional->code,    304, 'RSS conditional request returns not-modified status' );
    is( $conditional->content, '',  'RSS not-modified response has no body' );
};

done_testing;
