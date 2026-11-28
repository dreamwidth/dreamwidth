#!/usr/bin/perl
# t/plack-controller.t
#
# Tests that DW::Controller::Login renders through the full Plack stack.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use URI;

BEGIN {
    $LJ::_T_CONFIG = 1;
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use DW::Request::Plack;
use LJ::OpenID;
use LJ::Session;
use LJ::Test qw(temp_user);

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test: GET /login returns 200 with login form HTML
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "http://localhost/login?skin=global" );

    is( $res->code, 200, "GET /login returns 200" );
    like( $res->content, qr/<form/i, "Response contains a login form" );

    # /login must be marked no-cache: the form embeds a uniq-bound form_auth
    # token, so a shared cache serving one user's page to another would break
    # login with "Invalid form submission".
    like( $res->header('Cache-Control'), qr/no-cache/, "GET /login is marked no-cache" );
};

subtest 'HTTPS OpenID credential only authenticates at the provider' => sub {
    local $LJ::PROTOCOL = 'https';
    my $owner = temp_user();
    $owner->update_self( { status => 'A' } );
    my $session = LJ::Session->create( $owner, exptype => 'long', defer_login => 1 );
    my $site    = 'https://openid-provider.example/';
    ok( LJ::OpenID::add_trust( $owner, $site ), 'saved a trusted relying party' );

    my $cookie_app = sub {
        my ($env) = @_;
        DW::Request->reset;
        my $request = DW::Request::Plack->new($env);
        if ( $request->path eq '/logout' ) {
            LJ::Session->clear_master_cookie;
        }
        else {
            $session->update_master_cookie;
        }
        return [ 200, [ map { ( 'Set-Cookie' => "$_" ) } $request->header_out('Set-Cookie') ], [] ];
    };
    my $cookie_client = Plack::Test->create($cookie_app);
    my $scope         = sub {
        my ($response) = @_;
        my ($cookie)   = grep { /^__Secure-ljopenid=/ } $response->header('Set-Cookie');
        return $cookie // '';
    };
    my $issued = $scope->( $cookie_client->request( GET "$LJ::SITEROOT/login" ) );
    for my $attribute ( 'path=/openid/server', 'secure', 'httponly', 'samesite=none', 'expires=' ) {
        like( $issued, qr/;\s*\Q$attribute\E/i, "OpenID credential has $attribute" );
    }
    my ($credential) = split /;/, $issued;
    my $cleared = $scope->( $cookie_client->request( GET "$LJ::SITEROOT/logout" ) );
    like(
        $cleared,
        qr/^__Secure-ljopenid=;.*\bpath=\/openid\/server;.*expires=[^;]*1970/i,
        'logout expires the same scoped cookie'
    );
    {
        local $LJ::PROTOCOL      = 'http';
        local $LJ::IS_DEV_SERVER = 1;
        is( $scope->( $cookie_client->request( GET 'http://localhost/login' ) ),
            '', 'HTTP development login does not set the scoped cookie' );
    }
    my $regular_cookies;
    {
        no warnings 'redefine';
        local *LJ::get_secret = sub { return undef };

        my $response = $cookie_client->request( GET "$LJ::SITEROOT/login" );
        is( $scope->($response), $cleared,
            'failed replacement signing expires the same scoped cookie as logout' );
        my @regular = grep { /^lj(?:mastersession|loggedin)=/ } $response->header('Set-Cookie');
        is( scalar @regular, 2, 'ordinary login still sets both cookies without a signing key' );
        $regular_cookies = join '; ', map { ( split /;/, $_, 2 )[0] } @regular;
    }

    my $asserted_identity = sub {
        my ( $cb, $cookie ) = @_;
        my $res = $cb->(
            POST "$LJ::SITEROOT/openid/server",
            Cookie  => $cookie // '',
            Content => [
                'openid.mode'       => 'checkid_immediate',
                'openid.identity'   => $owner->journal_base . '/',
                'openid.return_to'  => "${site}verify",
                'openid.trust_root' => $site,
            ]
        );
        my $redirect = URI->new( $res->header('Location') // '' );
        my %params   = $redirect->can('query_form') ? $redirect->query_form : ();
        return $params{'openid.identity'};
    };
    test_psgi $app, sub {
        my $cb = shift;

        is(
            $asserted_identity->( $cb, $credential ),
            $owner->journal_base . '/',
            'trusted provider request succeeds with only the scoped cookie'
        );
        is( $asserted_identity->($cb),
            undef, 'provider does not assert an identity without a session' );
        {
            no warnings 'redefine';
            my $get_secret  = \&LJ::get_secret;
            my $key_lookups = 0;
            local *LJ::get_secret = sub {
                return $get_secret->(@_) unless @_;
                ++$key_lookups;
                return undef;
            };
            my $hmac             = \&LJ::Session::hmac_sha1_hex;
            my $missing_hmac_key = 0;
            local *LJ::Session::hmac_sha1_hex = sub {
                unless ( defined $_[1] && length $_[1] ) {
                    ++$missing_hmac_key;
                    return '';
                }
                return $hmac->(@_);
            };

            my ( $name, $value ) = split /=/, $credential, 2;
            my $malformed = LJ::durl($value);
            $malformed =~ s/:t[0-9]+:/:tinvalid:/;
            is( $asserted_identity->( $cb, "$name=" . LJ::eurl($malformed) ),
                undef, 'provider rejects a malformed signing timestamp' );
            is( $key_lookups, 0, 'malformed timestamps do not reach the signing-key store' );
            is( $asserted_identity->( $cb, $credential ),
                undef, 'provider rejects a credential whose signing key is unavailable' );
            is( $key_lookups, 1, 'provider checks the signing key for a well-formed credential' );
            is( $missing_hmac_key, 0, 'verification never computes an HMAC without a key' );
            my $signed_in = $cb->( GET "$LJ::SITEROOT/openid/options", Cookie => $regular_cookies );
            like( $signed_in->content, qr/\Q$site\E/,
                'ordinary login still shows the saved trusted site without the scoped key' );
        }
        my $options = $cb->( GET "$LJ::SITEROOT/openid/options", Cookie => $credential // '' );
        like( $options->header('Location') // '',
            qr{/login\?}, 'the scoped credential does not log the user in to options' );
        $session->destroy;
        is( $asserted_identity->( $cb, $credential ),
            undef, 'the scoped cookie cannot outlive the underlying session' );
    };
    LJ::get_db_writer()->do( 'DELETE FROM openid_trust WHERE userid=?', undef, $owner->id );
};

done_testing;
