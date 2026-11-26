# t/openid-insanejournal.t
#
# Tests for reusing legacy InsaneJournal OpenID accounts.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Digest::SHA qw( hmac_sha1_hex );
use HTTP::Response;
use IO::Socket::SSL qw( SSL_VERIFY_PEER );
use Net::OpenID::ClaimedIdentity;
use Net::OpenID::Consumer;
use Net::OpenID::VerifiedIdentity;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Importer::Report;
use DW::Importer::Sink::DryRun;
use DW::Importer::Sink::Live;
use LJ::OpenID;
use LJ::Test qw( temp_user );

my $IJ_OPENID_SERVER = 'https://www.insanejournal.com/openid/server.bml';

sub make_openid_args {
    my ( $claimed_url, %opts ) = @_;
    my $asserted_url = $opts{identity} // $claimed_url;
    my $now          = time();
    my $c_secret     = LJ::OpenID::consumer_secret($now);
    my $oic_sig      = substr( hmac_sha1_hex( $now, $c_secret ), 0, 20 );
    my $return_to    = ( $LJ::SITEROOT || 'https://dreamwidth.test' ) . '/openid/login';
    my %args         = (
        'openid.mode'         => 'id_res',
        'openid.identity'     => $asserted_url,
        'openid.return_to'    => $return_to,
        'openid.assoc_handle' => 'test-handle',
        'openid.signed'       => 'mode,identity,return_to',
        'openid.sig'          => 'test-sig',
        'oic.time'            => "$now-$oic_sig",
    );
    $args{'oic.identity'} = $claimed_url if $asserted_url ne $claimed_url;
    return \%args;
}

sub discovery_html {
    my ( $server, $delegate ) = @_;
    my $html = qq{<html><head><link rel="openid.server" href="$server" />};
    $html .= qq{<link rel="openid.delegate" href="$delegate" />} if defined $delegate;
    $html .= qq{</head><body></body></html>};
    return HTTP::Response->new( 200, 'OK', [ 'Content-Type' => 'text/html' ], $html );
}

sub run_with_openid_http {
    my ( $handler, $code ) = @_;
    my @requests;
    my $orig_get_useragent = \&LJ::get_useragent;

    no warnings 'redefine';
    local *LJ::get_useragent = sub {
        my $ua = $orig_get_useragent->(@_);
        $ua->remove_handler('request_send');
        $ua->add_handler(
            request_send => sub {
                my ( $request, $agent ) = @_;
                push @requests,
                    {
                    method          => $request->method,
                    uri             => $request->uri->as_string,
                    user_agent      => $request->header('User-Agent') // '',
                    verify_hostname => $agent->ssl_opts('verify_hostname'),
                    ssl_verify_mode => $agent->ssl_opts('SSL_verify_mode'),
                    alpn            => $agent->ssl_opts('SSL_alpn_protocols'),
                    max_redirect    => $agent->max_redirect,
                    isa_paranoid    => $agent->isa('LWP::UserAgent::Paranoid') ? 1 : 0,
                    };
                return $handler->( $request, $agent );
            }
        );
        return $ua;
    };

    my $rv = $code->( \@requests );
    return ( $rv, \@requests );
}

my $suffix       = temp_user()->id;
my $legacy_url   = "http://dw_openid_$suffix.insanejournal.com/";
my $verified_url = "https://dw-openid-$suffix.insanejournal.com/";
my $legacy       = LJ::User::load_identity_user( 'O', $legacy_url );
BAIL_OUT('Could not create the legacy OpenID fixture') unless $legacy;

subtest 'OpenID consumer applies InsaneJournal UA policy per request and redirect' => sub {
    local $LJ::SITENAME    = 'Test Dreamwidth';
    local $LJ::ADMIN_EMAIL = 'openid-admin@example.test';

    my $raw_ua = LJ::get_useragent( role => 'OpenID', timeout => 5 );
    isa_ok( $raw_ua, 'LWP::UserAgent::Paranoid', 'factory returns paranoid UA' );
    is( $raw_ua->ssl_opts('verify_hostname'), 0, 'factory default disables verify_hostname' );
    is( $raw_ua->ssl_opts('SSL_verify_mode'), 0, 'factory default disables SSL_verify_mode' );

    my $csr    = LJ::OpenID::consumer();
    my $csr_ua = $csr->ua;
    isa_ok( $csr_ua, 'LWP::UserAgent::Paranoid', 'consumer UA uses paranoid factory' );
    is( $csr_ua->ssl_opts('verify_hostname'),
        0, 'consumer does not globally enable hostname verification' );
    is( $csr_ua->ssl_opts('SSL_verify_mode'),
        0, 'consumer does not globally enable peer verification' );
    is_deeply( $csr_ua->ssl_opts('SSL_alpn_protocols'),
        ['http/1.1'], 'consumer UA preserves HTTP/1.1 ALPN' );
    is( $csr_ua->agent, $raw_ua->agent, 'consumer retains the factory default User-Agent' );

    my @urls = (
        'https://other.example.test/', 'https://insanejournal.com/', $verified_url,
        'https://insanejournal.com.example.test/',
        'https://notinsanejournal.com/',
    );
    my %redirects;
    @redirects{ @urls[ 0 .. 3 ] } = @urls[ 1 .. 4 ];

    my ( $response, $requests ) = run_with_openid_http(
        sub {
            my ($request) = @_;
            my $next = $redirects{ $request->uri->as_string };
            return $next
                ? HTTP::Response->new( 302, 'Found', [ Location => $next ] )
                : HTTP::Response->new(200);
        },
        sub { return LJ::OpenID::consumer()->ua->get( $urls[0] ); }
    );
    ok( $response->is_success, 'consumer follows redirects in and out of InsaneJournal' );
    is_deeply( [ map { $_->{uri} } @$requests ], \@urls, 'all redirect hops are sent' );
    for my $request (@$requests) {
        my $url   = $request->{uri};
        my $is_ij = $url eq $urls[1] || $url eq $urls[2];
        is( $request->{verify_hostname}, $is_ij ? 1 : 0, "$url has the expected hostname policy" );
        is(
            $request->{ssl_verify_mode},
            $is_ij ? SSL_VERIFY_PEER : 0,
            "$url has the expected peer policy"
        );
        is(
            $request->{user_agent},
            $is_ij ? $LJ::SITENAME : $raw_ua->agent,
            "$url has the expected User-Agent without administrative contact information"
        );
    }
};

subtest 'ordinary lookups and unverified calls do not alias legacy accounts' => sub {
    my ( $ordinary, $reqs ) = run_with_openid_http( sub { return HTTP::Response->new(500); },
        sub { return LJ::User::load_existing_identity_user( 'O', $verified_url ); } );
    ok( !$ordinary, 'an ordinary URL lookup does not match the legacy account' );
    is( scalar @$reqs, 0, 'ordinary lookup sends no provider requests' );

    my $unv_legacy =
        LJ::User::load_identity_user( 'O', "http://dw_openid_${suffix}_unv.insanejournal.com/" );
    BAIL_OUT('Could not create unverified-call legacy fixture') unless $unv_legacy;
    my $unv_https = "https://dw-openid-${suffix}-unv.insanejournal.com/";
    my ( $unv_user, $unv_reqs ) = run_with_openid_http(
        sub { return HTTP::Response->new( 302, 'Found', [ Location => $unv_https ] ); },
        sub { return LJ::User::load_identity_user( 'O', $unv_https, undef ); }
    );
    ok( $unv_user, 'unverified load_identity_user creates a canonical account' );
    isnt( $unv_user->id, $unv_legacy->id, 'unverified call does not reuse the legacy account' );
    is( scalar @$unv_reqs, 0, 'unverified call sends no provider confirmation requests' );
};

subtest
'assertion boundary rejects unverified discovery, wrong provider, delegation, and synthetic identities'
    => sub {
    my $secure_legacy_url = "https://dw_openid_$suffix.insanejournal.com/";

    # 1. Consumer whose UA still has factory-default disabled TLS verification.
    my ( $unverified_tls_u, $reqs1 ) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html($IJ_OPENID_SERVER)
                if $req->method eq 'GET' && $req->uri->as_string eq $verified_url;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $IJ_OPENID_SERVER;
            return HTTP::Response->new( 302, 'Found', [ Location => $verified_url ] )
                if $req->method eq 'HEAD' && $req->uri->as_string eq $secure_legacy_url;
            return HTTP::Response->new(404);
        },
        sub {
            my $weak_ua = LJ::get_useragent( role => 'OpenID', timeout => 5 );
            my $csr     = Net::OpenID::Consumer->new(
                ua              => $weak_ua,
                args            => make_openid_args($verified_url),
                consumer_secret => \&LJ::OpenID::consumer_secret,
                required_root   => $LJ::SITEROOT,
            );
            my $vident = $csr->verified_identity;
            ok( $vident, 'fixture produces verified identity on unverified-TLS consumer' );
            return LJ::User::load_identity_user( 'O', $verified_url, $vident );
        }
    );
    ok( !$unverified_tls_u, 'legacy match is rejected when consumer UA lacked TLS verification' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$reqs1 ),
        0, 'no confirmation HEAD is sent when consumer TLS verification was disabled' );
    ok(
        !LJ::User::load_existing_identity_user( 'O', $verified_url ),
        'rejected unverified-TLS assertion does not create a canonical account'
    );

    # 2. Assertion verified by an untrusted OpenID server rather than InsaneJournal.
    my $evil_server = 'https://evil.example/openid/server.bml';
    my ( $wrong_op_u, $reqs2 ) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html($evil_server)
                if $req->method eq 'GET' && $req->uri->as_string eq $verified_url;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $evil_server;
            return HTTP::Response->new( 302, 'Found', [ Location => $verified_url ] )
                if $req->method eq 'HEAD' && $req->uri->as_string eq $secure_legacy_url;
            return HTTP::Response->new(404);
        },
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( !$wrong_op_u, 'legacy match is rejected for an assertion from a non-InsaneJournal server' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$reqs2 ),
        0, 'no confirmation HEAD is sent for a non-InsaneJournal server' );
    ok(
        !LJ::User::load_existing_identity_user( 'O', $verified_url ),
        'rejected wrong-provider assertion does not create a canonical account'
    );

    # 3. Delegated identity pointing to a different journal URL.
    my $delegated_url = "https://other-$suffix.insanejournal.com/";
    my ( $delegated_u, $reqs3 ) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html( $IJ_OPENID_SERVER, $delegated_url )
                if $req->method eq 'GET' && $req->uri->as_string eq $verified_url;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $IJ_OPENID_SERVER;
            return HTTP::Response->new( 302, 'Found', [ Location => $verified_url ] )
                if $req->method eq 'HEAD' && $req->uri->as_string eq $secure_legacy_url;
            return HTTP::Response->new(404);
        },
        sub {
            my $csr = LJ::OpenID::consumer(
                make_openid_args( $verified_url, identity => $delegated_url ) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( !$delegated_u, 'legacy match is rejected when the identity delegates to another URL' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$reqs3 ),
        0, 'no confirmation HEAD is sent for a delegated identity' );
    ok(
        !LJ::User::load_existing_identity_user( 'O', $verified_url ),
        'rejected delegated assertion does not create a canonical account'
    );

    # 4. Bare constructed VerifiedIdentity without consumer or signed fields.
    my ( $synthetic_u, $reqs4 ) = run_with_openid_http(
        sub {
            return HTTP::Response->new( 302, 'Found', [ Location => $verified_url ] );
        },
        sub {
            my $identity = Net::OpenID::VerifiedIdentity->new(
                claimed_identity => Net::OpenID::ClaimedIdentity->new( identity => $verified_url )
            );
            return LJ::User::load_identity_user( 'O', $verified_url, $identity );
        }
    );
    ok( !$synthetic_u,
        'legacy match is rejected for a bare synthetic VerifiedIdentity without consumer proof' );
    is( scalar @$reqs4, 0, 'no confirmation HEAD is sent for a synthetic VerifiedIdentity' );
    ok(
        !LJ::User::load_existing_identity_user( 'O', $verified_url ),
        'rejected synthetic VerifiedIdentity does not create a canonical account'
    );
    };

subtest 'provider confirmation checks TLS, User-Agent, no-redirect, and persists canonical key' =>
    sub {
    local $LJ::SITENAME    = 'Test Dreamwidth';
    local $LJ::ADMIN_EMAIL = 'openid-admin@example.test';
    my $secure_legacy_url = "https://dw_openid_$suffix.insanejournal.com/";
    my $hop_url           = "https://hop-$suffix.insanejournal.com/";
    my $head_response     = HTTP::Response->new(503);

    my $handler = sub {
        my ($req) = @_;
        return discovery_html($IJ_OPENID_SERVER)
            if $req->method eq 'GET' && $req->uri->as_string eq $verified_url;
        return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
            if $req->method eq 'POST' && $req->uri->as_string eq $IJ_OPENID_SERVER;
        return $head_response
            if $req->method eq 'HEAD' && $req->uri->as_string eq $secure_legacy_url;
        return HTTP::Response->new( 302, 'Found', [ Location => $verified_url ] )
            if $req->uri->as_string eq $hop_url;
        return HTTP::Response->new(404);
    };

    # Unreachable provider (503) + inspect HEAD request-boundary TLS/UA/redirect settings.
    my ( $u503, $reqs503 ) = run_with_openid_http(
        $handler,
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( !$u503, 'the provider must be reachable to confirm the legacy account' );
    my ($head_req) = grep { $_->{method} eq 'HEAD' } @$reqs503;
    ok( $head_req, 'confirmation sent a HEAD request to the legacy HTTPS host' );
    is( $head_req->{uri}, $secure_legacy_url, 'HEAD targeted the exact legacy HTTPS root' );
    ok( $head_req->{isa_paranoid},    'HEAD used the paranoid UA factory' );
    ok( $head_req->{verify_hostname}, 'HEAD explicitly enabled verify_hostname' );
    ok( ( $head_req->{ssl_verify_mode} // 0 ) & SSL_VERIFY_PEER,
        'HEAD explicitly enabled SSL_VERIFY_PEER' );
    is_deeply( $head_req->{alpn}, ['http/1.1'], 'HEAD preserved HTTP/1.1 ALPN' );
    is( $head_req->{max_redirect}, 0, 'HEAD disabled following redirects' );
    unlike( $head_req->{user_agent},
        qr/libwww-perl/i,
        'HEAD sent an identifying Dreamwidth User-Agent rather than libwww-perl' );
    is( $head_req->{user_agent},
        $LJ::SITENAME, 'HEAD does not send administrative contact information' );

    # Redirect to wrong path on verified host.
    $head_response = HTTP::Response->new( 302, 'Found', [ Location => "${verified_url}profile" ] );
    my ($u_wrong_loc) = run_with_openid_http(
        $handler,
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( !$u_wrong_loc, 'a redirect to a different URL does not confirm the legacy account' );

    # Indirect redirect chain (legacy -> hop -> verified_url) must be rejected without following.
    $head_response = HTTP::Response->new( 302, 'Found', [ Location => $hop_url ] );
    my ( $u_indirect, $reqs_indirect ) = run_with_openid_http(
        $handler,
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( !$u_indirect, 'an indirect redirect chain does not confirm the legacy account' );
    is( scalar( grep { $_->{uri} eq $hop_url } @$reqs_indirect ),
        0, 'no request followed the intermediate redirect target' );
    ok(
        !LJ::User::load_existing_identity_user( 'O', $verified_url ),
        'failed confirmation does not create a separate canonical account'
    );

    # Direct 302 to exact verified URL confirms legacy account and persists canonical key.
    $head_response = HTTP::Response->new( 302, 'Found', [ Location => $verified_url ] );
    my ( $claimed, $reqs_ok ) = run_with_openid_http(
        $handler,
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    is( $claimed && $claimed->id,
        $legacy->id,
        'provider-confirmed verified assertion resolves to the existing legacy account' );
    ok(
        scalar( grep { $_->{method} eq 'GET' && $_->{verify_hostname} } @$reqs_ok ),
        'OpenID discovery ran with TLS hostname verification enabled'
    );
    ok(
        scalar( grep { $_->{method} eq 'POST' && $_->{verify_hostname} } @$reqs_ok ),
        'OpenID check_authentication ran with TLS hostname verification enabled'
    );

    # Subsequent live and dry-run imports resolve to the same account instead of splitting it.
    my $canonical_http = "http://dw-openid-$suffix.insanejournal.com/";
    my $importer_u     = temp_user();
    my $live_sink      = DW::Importer::Sink::Live->new(
        u    => $importer_u,
        data => { userid => $importer_u->id, import_data_id => 1 },
    );
    my $dryrun_sink = DW::Importer::Sink::DryRun->new(
        live   => $live_sink,
        report => DW::Importer::Report->new,
    );
    is( $live_sink->identity_user($canonical_http),
        $legacy->id, 'subsequent live import resolves to the confirmed legacy account' );
    is( $dryrun_sink->identity_user($canonical_http),
        $legacy->id, 'subsequent dry-run import resolves to the confirmed legacy account' );

    # Subsequent verified login/claim resolves directly to the same account with no HEAD probe.
    my ( $again, $reqs_again ) = run_with_openid_http(
        $handler,
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    is( $again && $again->id,
        $legacy->id, 'subsequent verified resolution stays on the confirmed legacy account' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$reqs_again ),
        0, 'subsequent verified resolution needs no repeat confirmation HEAD' );
    is( $legacy->openid_identity, $canonical_http,
        'confirmed legacy account now holds the canonical HTTP identity key' );
    };

subtest 'verified boundary and exact-precedence cases with legacy candidates present' => sub {

    # 1. Non-root path on same InsaneJournal host with legacy candidate present.
    my $path_legacy =
        LJ::User::load_identity_user( 'O', "http://dw_openid_${suffix}_path.insanejournal.com/" );
    BAIL_OUT('Could not create path-boundary legacy fixture') unless $path_legacy;
    my $other_path_url = "https://dw-openid-${suffix}-path.insanejournal.com/other/";
    my ( $path_user, $path_reqs ) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html($IJ_OPENID_SERVER)
                if $req->method eq 'GET' && $req->uri->as_string eq $other_path_url;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $IJ_OPENID_SERVER;
            return HTTP::Response->new( 302, 'Found', [ Location => $other_path_url ] )
                if $req->method eq 'HEAD';
            return HTTP::Response->new(404);
        },
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($other_path_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( $path_user, 'verified non-root path creates its own account' );
    isnt( $path_user->id, $path_legacy->id,
        'verified non-root path on the same journal host does not select the legacy account' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$path_reqs ),
        0, 'non-root path sends no confirmation HEAD request' );

    # 2. LiveJournal verified HTTPS URL with legacy underscore candidate present.
    my $lj_legacy =
        LJ::User::load_identity_user( 'O', "http://dw_openid_$suffix.livejournal.com/" );
    BAIL_OUT('Could not create LiveJournal legacy fixture') unless $lj_legacy;
    my $lj_verified_url = "https://dw-openid-$suffix.livejournal.com/";
    my $lj_server       = 'https://www.livejournal.com/openid/server.bml';
    my ( $lj_user, $lj_reqs ) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html($lj_server)
                if $req->method eq 'GET' && $req->uri->as_string eq $lj_verified_url;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $lj_server;
            return HTTP::Response->new( 302, 'Found', [ Location => $lj_verified_url ] )
                if $req->method eq 'HEAD';
            return HTTP::Response->new(404);
        },
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($lj_verified_url) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    ok( $lj_user, 'verified LiveJournal identity resolves without failing' );
    isnt( $lj_user->id, $lj_legacy->id,
        'verified LiveJournal identity does not select the underscore legacy account' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$lj_reqs ),
        0, 'LiveJournal identity sends no confirmation HEAD request' );

    # 3. Exact precedence with two competing stored rows via the verified HTTPS path.
    my $canonical_http  = "http://dw-openid-$suffix-exact.insanejournal.com/";
    my $canonical_https = "https://dw-openid-$suffix-exact.insanejournal.com/";
    my $alias_http      = "http://dw_openid_${suffix}_exact.insanejournal.com/";
    my $canonical       = LJ::User::load_identity_user( 'O', $canonical_http );
    my $alias           = LJ::User::load_identity_user( 'O', $alias_http );
    BAIL_OUT('Could not create exact-precedence fixtures') unless $canonical && $alias;
    isnt( $canonical->id, $alias->id, 'both stored spellings can already have distinct accounts' );

    my ( $exact_user, $exact_reqs ) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html($IJ_OPENID_SERVER)
                if $req->method eq 'GET' && $req->uri->as_string eq $canonical_https;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $IJ_OPENID_SERVER;
            return HTTP::Response->new( 302, 'Found', [ Location => $canonical_https ] )
                if $req->method eq 'HEAD';
            return HTTP::Response->new(404);
        },
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($canonical_https) );
            my $err;
            return LJ::User::load_from_consumer( $csr, \$err );
        }
    );
    is( $exact_user && $exact_user->id,
        $canonical->id,
        'verified HTTPS resolution selects the exact canonical account over alias' );
    is( scalar( grep { $_->{method} eq 'HEAD' } @$exact_reqs ),
        0, 'exact match sends no confirmation HEAD request' );
    is( LJ::User::load_existing_identity_user( 'O', $alias_http )->id,
        $alias->id, 'competing legacy account remains distinct and untouched' );
};

subtest 'legacy migration serializes with account creation for either canonical spelling' => sub {
    my $alias_host      = "dw_openid_${suffix}_contended.insanejournal.com";
    my $canonical_host  = "dw-openid-$suffix-contended.insanejournal.com";
    my $alias_http      = "http://$alias_host/";
    my $canonical_http  = "http://$canonical_host/";
    my $canonical_https = "https://$canonical_host/";
    my $alias           = LJ::User::load_identity_user( 'O', $alias_http );
    BAIL_OUT('Could not create contended legacy fixture') unless $alias;

    my @competing_users;
    my ($migrated) = run_with_openid_http(
        sub {
            my ($req) = @_;
            return discovery_html($IJ_OPENID_SERVER)
                if $req->method eq 'GET' && $req->uri->as_string eq $canonical_https;
            return HTTP::Response->new( 200, 'OK', [], "is_valid:true\n" )
                if $req->method eq 'POST' && $req->uri->as_string eq $IJ_OPENID_SERVER;
            if ( $req->method eq 'HEAD' && $req->uri->as_string eq "https://$alias_host/" ) {
                @competing_users = map { LJ::User::load_identity_user( 'O', $_ ) }
                    ( $canonical_https, $canonical_http );
                return HTTP::Response->new( 302, 'Found', [ Location => $canonical_https ] );
            }
            return HTTP::Response->new(404);
        },
        sub {
            my $csr = LJ::OpenID::consumer( make_openid_args($canonical_https) );
            return LJ::User::load_from_consumer($csr);
        }
    );
    is_deeply(
        \@competing_users,
        [ undef, undef ],
        'both competing writers fail closed during migration'
    );
    is( $migrated && $migrated->id, $alias->id, 'verified migration preserves the legacy account' );
    my $dbh  = LJ::get_db_writer();
    my $rows = $dbh->selectall_arrayref(
        'SELECT identity, userid FROM identitymap WHERE idtype=? AND identity IN (?, ?, ?)',
        undef, 'O', $alias_http, $canonical_https, $canonical_http, );
    is_deeply(
        $rows,
        [ [ $canonical_http, $alias->id ] ],
        'only the migrated canonical row exists'
    );
    for my $url ( $canonical_https, $canonical_http ) {
        my $retried = LJ::User::load_identity_user( 'O', $url );
        is( $retried && $retried->id, $alias->id,
            "$url resolves to the migrated account on retry" );
    }

    my $created_https = "https://dw-openid-$suffix-https-first.insanejournal.com/";
    my $created_http  = "http://dw-openid-$suffix-https-first.insanejournal.com/";
    my $created       = LJ::User::load_identity_user( 'O', $created_https );
    BAIL_OUT('Could not create canonical HTTPS fixture') unless $created;
    my $from_http = LJ::User::load_identity_user( 'O', $created_http );
    is( $from_http && $from_http->id,
        $created->id, 'HTTP creation reuses an existing HTTPS account' );
};

done_testing();
