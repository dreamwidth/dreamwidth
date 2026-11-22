#!/usr/bin/perl
#
# t/xpost-protocol.t
#
# Test crosspost protocol discovery and LJ XML-RPC requests without ljlib.pl.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use Test::More;

use lib "$ENV{LJHOME}/cgi-bin";
use HTTP::Response;
use LWP::UserAgent;
use XMLRPC::Lite;
use DW::External::XPostProtocol;
use DW::External::XPostProtocol::LJXMLRPC;

{

    package XPostProtocolTest::Account;

    sub serviceurl { return $_[0]->{serviceurl} }
    sub serverhost { return $_[0]->{serverhost} }
    sub recordlink { return $_[0]->{recordlink} }
}

sub xmlrpc_response {
    my $body = XMLRPC::Serializer->envelope(@_);
    return HTTP::Response->new( 200, 'OK', [ 'Content-Type' => 'text/xml' ], $body );
}

sub xmlrpc_exchange {
    my ( $exercise, @responses ) = @_;
    my @requests;
    no warnings 'redefine';
    local *LWP::UserAgent::request = sub {
        my ( undef, $request ) = @_;
        my $call = XMLRPC::Deserializer->new->deserialize( $request->content );
        push @requests, [ $request->uri->as_string, $call->method, $call->paramsin ];
        return shift(@responses) // die 'Unexpected outgoing XML-RPC request';
    };
    my $result = $exercise->();
    return ( $result, \@requests );
}

my $protocol = DW::External::XPostProtocol->get_protocol('lj');
isa_ok( $protocol, 'DW::External::XPostProtocol::LJXMLRPC' );
BAIL_OUT('LJ crosspost protocol did not register') unless $protocol;

subtest 'protocol selection and unsupported crossposting' => sub {
    my %protocols = DW::External::XPostProtocol->get_all_protocols;
    is( $protocols{lj}, $protocol, 'registered LJ protocol is available for selection' );
    is( DW::External::XPostProtocol->get_protocol('unknown'),
        undef, 'unknown protocol unavailable' );

    my $result = DW::External::XPostProtocol->crosspost;
    is( $result->{success}, 0, 'base protocol does not report unimplemented crossposts as sent' );
    like( $result->{error}, qr/not implemented/i, 'base protocol explains the failure' );
};

my $host          = 'https://journal.example.invalid';
my $default_url   = "$host/interface/xmlrpc";
my $custom_url    = "$host/custom/rpc";
my $challenge_rpc = 'LJ.XMLRPC.getchallenge';
my $challenge     = { challenge => 'test-nonce' };

subtest 'server validation tries the standard path for a bare host' => sub {
    my ( $result, $requests ) = xmlrpc_exchange(
        sub { [ $protocol->validate_server($host) ] },
        HTTP::Response->new( 404, 'Not Found' ),
        xmlrpc_response( response => $challenge_rpc, $challenge ),
    );
    is_deeply( $result, [ 1, $default_url ], 'validation returns the working endpoint' );
    is_deeply(
        $requests,
        [ [ $host, $challenge_rpc ], [ $default_url, $challenge_rpc ] ],
        'checks the supplied URL before trying the standard path'
    );
};

subtest 'an XML-RPC fault is not a valid custom endpoint' => sub {
    my ( $result, $requests ) = xmlrpc_exchange(
        sub { scalar $protocol->validate_server($custom_url) },
        xmlrpc_response( fault => 100, 'Unknown method' ),
    );
    is( $result, 0, 'rejects an endpoint that does not serve the LJ challenge' );
    is_deeply( $requests, [ [ $custom_url, $challenge_rpc ] ], 'preserves the supplied path' );
};

subtest 'LJ passwords are hashed unless blank' => sub {
    is(
        $protocol->encrypt_password('password'),
        '5f4dcc3b5aa765d61d8327deb882cf99',
        'nonblank password is encoded as hexadecimal MD5'
    );
    is( $protocol->encrypt_password(''),    '',    'blank password remains blank' );
    is( $protocol->encrypt_password(undef), undef, 'missing password remains missing' );
};

local $LJ::SITENAME    = 'Dreamwidth Test';
local $LJ::ADMIN_EMAIL = 'test@example.invalid';
my $auth =
    { username => 'journal-owner', encrypted_password => $protocol->encrypt_password('password') };
my $edit_rpc       = 'LJ.XMLRPC.editevent';
my $delete_request = {
    ver            => 1,
    auth_method    => 'challenge',
    username       => 'journal-owner',
    auth_challenge => 'test-nonce',
    auth_response  => '5031e615350cb1545a0666df8146db43',
    event          => '',
    itemid         => 42,
};

subtest 'deleting a crosspost submits an authenticated blank edit' => sub {
    my $account = bless { serverhost => 'journal.example.invalid', recordlink => 1 },
        'XPostProtocolTest::Account';
    my $remote_entry = { itemid => 42, url => "$host/42.html" };
    my ( $result, $requests ) = xmlrpc_exchange(
        sub { $protocol->crosspost( $account, $auth, undef, 42, 1 ) },
        xmlrpc_response( response => $challenge_rpc, $challenge ),
        xmlrpc_response( response => $edit_rpc,      $remote_entry ),
    );
    is_deeply(
        $requests,
        [ [ $default_url, $challenge_rpc, {} ], [ $default_url, $edit_rpc, $delete_request ] ],
        'uses the default HTTPS endpoint and sends the challenge response, not the password'
    );
    is_deeply(
        $result,
        { success => 1, url => $remote_entry->{url}, reference => $remote_entry },
        'returns the remote entry reference with its requested link'
    );
};

subtest 'an already deleted crosspost returns a distinct failure' => sub {
    my $account = bless { serviceurl => $custom_url }, 'XPostProtocolTest::Account';
    my ( $result, $requests ) = xmlrpc_exchange(
        sub { $protocol->crosspost( $account, $auth, undef, 42, 1 ) },
        xmlrpc_response( response => $challenge_rpc, $challenge ),
        xmlrpc_response( fault    => 302,            'Entry has been deleted' ),
    );
    is_deeply(
        $requests,
        [ [ $custom_url, $challenge_rpc, {} ], [ $custom_url, $edit_rpc, $delete_request ] ],
        'sends authentication and the edit to the configured endpoint'
    );
    is( $result->{success}, 0, 'remote fault is not reported as success' );
    is( $result->{code}, 'entry_deleted', 'fault 302 identifies a missing remote entry' );
};

my @ljlib = grep { m{(?:^|/)ljlib\.pl\z} } keys %INC, values %INC;
is_deeply( \@ljlib, [], 'ljlib.pl was not loaded in this process' );

done_testing();
