#!/usr/bin/perl
# Regression coverage for $LJ::DISABLE_PROTOCOL{getevents}'s third callback
# argument: LJ::Protocol.pm's getevents constructs a DW::BML::RequestAdapter
# directly from the current DW::Request, or passes undef outside a request --
# the held external callback ABI this file locks in. See
# doc/BML-PROTOCOL-PAGESTATS.md for the original characterization.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::BML::RequestAdapter;
use DW::Request;
use DW::Request::Plack;
use LJ::Protocol;
use LJ::Test qw(temp_user);

my $u = temp_user();
$u->update_self( { status => 'A' } );

my @calls;
local %LJ::DISABLE_PROTOCOL = (
    getevents => sub {
        my ( $req, $flags, $apache_r ) = @_;
        push @calls, { req => $req, flags => $flags, apache_r => $apache_r };
        return 'rejected by test callback';
    }
);

subtest 'callback receives a DW::BML::RequestAdapter wrapping the current request' => sub {
    @calls = ();
    test_psgi(
        app => sub {
            my $env = shift;
            DW::Request->reset;
            DW::Request->get( plack_env => $env );

            my $err;
            my $res = LJ::Protocol::do_request(
                'getevents',
                {
                    username   => $u->user,
                    selecttype => 'lastn',
                    howmany    => 1,
                },
                \$err,
                { noauth => 1 }
            );

            return [
                200,
                [ 'Content-Type' => 'text/plain' ],
                [ defined $res ? "RESULT" : "UNDEF:$err" ]
            ];
        },
        client => sub {
            my $cb  = shift;
            my $res = $cb->( GET '/protocol-disable-callback-marker' );
            is(
                $res->content,
                'UNDEF:311:rejected by test callback',
                'the callback short-circuits the request exactly as before'
            );
        },
    );
    DW::Request->reset;

    is( scalar @calls, 1, 'callback fired exactly once' );
    my $apache_r = $calls[0]->{apache_r};
    isa_ok( $apache_r, 'DW::BML::RequestAdapter', 'third argument is a DW::BML::RequestAdapter' );
    is(
        $apache_r->uri,
        '/protocol-disable-callback-marker',
        'the adapter wraps the actual current DW::Request, not an empty/mock one'
    );
    is( $calls[0]->{req}->{username}, $u->user, 'callback receives the real $req' );
    is( ref $calls[0]->{flags},       'HASH',   'callback receives the real $flags' );
};

subtest 'callback receives undef with no active request' => sub {
    @calls = ();
    DW::Request->reset;
    ok( !DW::Request->get, 'fixture confirms no active request' );

    my $err;
    my $res = LJ::Protocol::do_request(
        'getevents',
        {
            username   => $u->user,
            selecttype => 'lastn',
            howmany    => 1,
        },
        \$err,
        { noauth => 1 }
    );

    is( $res, undef, 'the request is still rejected with no active DW::Request' );
    is(
        $err,
        '311:rejected by test callback',
        'the callback still short-circuits the request with no active DW::Request'
    );
    is( scalar @calls,         1,     'callback fired exactly once' );
    is( $calls[0]->{apache_r}, undef, 'third argument is undef with no active request' );
};

done_testing;
