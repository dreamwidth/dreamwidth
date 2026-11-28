#!/usr/bin/perl
# t/oauth-request.t
#
# Tests OAuth request tokens and the protected-resource body hash extension.
#
# Authors:
#      Alex Southwell <saphid@gmail.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";

use Test::More;
use Digest::SHA qw(sha1_base64);
use Net::OAuth;

use DW::OAuth::Consumer;
use DW::OAuth::LocalProtectedResourceRequest;
use DW::OAuth::Request;
use LJ::MemCache;

{

    package OAuthRequestTest::Memcached;

    sub new { return bless {}, $_[0] }

    sub get {
        my ( $cache, $key ) = @_;
        return $cache->{ ref $key ? $key->[1] : $key };
    }

    sub set {
        my ( $cache, $key, $value ) = @_;
        $cache->{ ref $key ? $key->[1] : $key } = $value;
        return 1;
    }

    sub delete {
        my ( $cache, $key ) = @_;
        return delete $cache->{ ref $key ? $key->[1] : $key };
    }
}

my $request_class = 'DW::OAuth::Request';
local $LJ::SECRETS{oauth_request} = 'request-test-secret';

subtest 'request token lifecycle' => sub {
    LJ::MemCache::set_memcache( OAuthRequestTest::Memcached->new );

    eval { $request_class->new(undef) };
    like( $@, qr/Invalid consumer/, 'cannot issue a token without a consumer' );

    my $consumer = DW::OAuth::Consumer->new_from_row( { consumer_id => 42, token => 'consumer' } );
    my $request  = $request_class->new( $consumer, user_id => 99 );
    my $token    = $request->token;

    like( $token,           qr/\A[A-Za-z0-9_-]{16}\z/, 'default request token is URL-safe' );
    like( $request->secret, qr/\A[A-Za-z0-9_-]{43}\z/, 'request has a URL-safe signing secret' );
    like( $request->verifier, qr/\A[0-9]{8}\z/, 'out-of-band verifier is an eight-digit PIN' );
    is( $request->callback,             'oob',         'defaults to an out-of-band callback' );
    is( $request->consumer_id,          $consumer->id, 'token is issued for the consumer' );
    is( $request_class->want($request), $request,      'want accepts an existing request object' );

    my $reloaded = $request_class->want($token);
    isa_ok( $reloaded, $request_class );
    isnt( $reloaded, $request, 'token lookup reconstructs a separate object' );
    is( $reloaded->token,    $token,             'token survives the cache round trip' );
    is( $reloaded->secret,   $request->secret,   'signing secret survives the cache round trip' );
    is( $reloaded->verifier, $request->verifier, 'verifier survives the cache round trip' );
    is( $reloaded->consumer_id, $consumer->id, 'consumer survives the cache round trip' );
    is( $reloaded->createtime, $request->createtime,
        'creation time survives the cache round trip' );
    is( $reloaded->userid, undef, 'issuance does not associate the supplied user with the token' );

    $reloaded->userid(99);
    $reloaded->save;
    is( $request_class->from_token($token)->userid, 99, 'user association can be saved later' );

    ok( !$reloaded->used, 'the loaded token starts unused' );
    $reloaded->delete;
    ok( $reloaded->used, 'deletion marks the request as used' );
    is( $request_class->from_token($token), undef, 'a deleted token can no longer be looked up' );

    my $malformed = $request_class->new_from_row( { token => 'bad/token' } );
    $malformed->save;
    is( $request_class->from_token( $malformed->token ),
        undef, 'a malformed token is rejected even if cached' );
};

subtest 'callback requests' => sub {
    LJ::MemCache::set_memcache( OAuthRequestTest::Memcached->new );
    my $callback = 'https://client.example.test/oauth?step=finish';
    my $request =
        $request_class->new( undef, consumer_id => 42, callback => $callback, simple_token => 1 );

    like( $request->token, qr/\A[0-9]{8}\z/, 'a simple request token is an eight-digit PIN' );
    like( $request->verifier, qr/\A[A-Za-z0-9_-]{27}\z/,
        'a callback uses the full URL-safe verifier' );
    is( $request_class->from_token( $request->token )->callback,
        $callback, 'callback URL is preserved in cache' );
};

subtest 'protected-resource body hash' => sub {
    my $class          = 'DW::OAuth::LocalProtectedResourceRequest';
    my %request_params = (
        protocol_version          => Net::OAuth::PROTOCOL_VERSION_1_0A,
        consumer_secret           => 'client-test-secret',
        token_secret              => 'token-test-secret',
        request_method            => 'POST',
        request_url               => 'https://api.example.test/resource',
        allowed_signature_methods => ['HMAC-SHA1'],
    );
    my %message_params = (
        consumer_key     => 'client-key',
        token            => 'access-token',
        signature_method => 'HMAC-SHA1',
        timestamp        => 1_700_000_000,
        nonce            => 'nonce',
    );
    my $body_hash = sha1_base64('') . '=';
    my $request   = $class->new( %request_params, %message_params, body_hash => $body_hash );
    $request->sign;

    my $header = $request->to_authorization_header;
    like( $header, qr/\boauth_body_hash=/, 'the body hash is sent as an OAuth parameter' );
    my $parsed = $class->from_authorization_header( $header, %request_params );
    is( $parsed->body_hash, $body_hash, 'the decoded body hash round-trips through the header' );
    ok( $parsed->verify, 'the signed request with the body hash verifies' );

    $parsed->body_hash( sha1_base64('different body') . '=' );
    ok( !$parsed->verify, 'changing the body hash invalidates the signature' );

    my $without_hash = $class->new( %request_params, %message_params );
    $without_hash->sign;
    $header = $without_hash->to_authorization_header;
    unlike( $header, qr/\boauth_body_hash=/, 'the header can omit the optional body hash' );
    $parsed = $class->from_authorization_header( $header, %request_params );
    ok( $parsed->verify, 'a signed request without a body hash still verifies' );
};

my @loaded_ljlib = grep { defined && m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC );
is_deeply( \@loaded_ljlib, [], 'the test does not load ljlib.pl' );

done_testing;
