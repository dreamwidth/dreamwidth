# t/session-trust.t
#
# Tests the "ljtrust" trust cookie in LJ::Session: a long-lived, HMAC-signed
# marker that a browser recently held a valid session, bound to the browser's
# ljuniq ident. Covers issuance (update_trust_cookie / update_master_cookie),
# validation (trusted_anon_user), the uniq binding, tampering, staleness,
# cookie-generation rotation, live standing re-checks, and that logout leaves
# the cookie alone.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);
use LJ::Session;
use LJ::UniqCookie;

# Minimal fake request: a readable cookie jar plus capture of everything the
# code under test sets via add_cookie.
package FakeRequest;

sub new { my ( $class, %a ) = @_; bless { jar => {}, set => [], %a }, $class }
sub cookie        { $_[0]->{jar}{ $_[1] } }
sub get_remote_ip { "127.0.0.1" }
sub header_in     { "" }

sub add_cookie {
    my ( $self, %args ) = @_;
    push @{ $self->{set} }, \%args;
}

# cookies set with a given name, in order
sub set_cookies {
    my ( $self, $name ) = @_;
    return grep { $_->{name} eq $name } @{ $self->{set} };
}

package main;

my $req;
no warnings 'redefine';
local *DW::Request::get = sub { $req };

my $uniq = "abcdefghij12345";
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = $uniq;

my $u = temp_user();
$u->update_self( { status => 'A' } );    # validated email

sub trusted { return LJ::Session->trusted_anon_user }

note("issuance via update_trust_cookie");
my $cookie_value;
{
    $req = FakeRequest->new;
    my $sess = bless { userid => $u->id }, 'LJ::Session';
    $sess->update_trust_cookie;

    my @set = $req->set_cookies('ljtrust');
    ok( scalar @set, "update_trust_cookie set an ljtrust cookie" );
    $cookie_value = $set[0]->{value};
    like( $cookie_value, qr/^v1:u\d+:t\d+:g[0-9a-f]{40}\/\//, "cookie has expected format" );
    ok( $set[0]->{httponly}, "cookie is httponly" );
}

note("valid cookie resolves to the user");
{
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $cookie_value;
    my $got = trusted();
    ok( $got && $got->equals($u), "trusted_anon_user returns the issuing user" );
}

note("no cookie, no trust");
{
    $req = FakeRequest->new;
    ok( !trusted(), "no ljtrust cookie -> undef" );
}

note("verdict is not memoized across requests");
{
    # a verdict memoized in state that outlives the request would leak between
    # visitors on a persistent worker (the #3643 bug); simulate back-to-back
    # requests from different browsers on one worker and check each gets its
    # own answer
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $cookie_value;
    ok( trusted(), "request with a valid cookie -> trusted" );

    $req = FakeRequest->new;
    ok( !trusted(), "next request without the cookie -> not trusted" );

    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $cookie_value;
    ok( trusted(), "and trust returns with the cookie" );
}

note("bound to the uniq ident");
{
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $cookie_value;
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = "zzzzzzzzzz54321";
    ok( !trusted(), "same cookie under a different uniq -> undef" );
}

note("tampered signature");
{
    $req = FakeRequest->new;
    ( my $tampered = $cookie_value ) =~ tr/0-9/1-90/;
    $req->{jar}{ljtrust} = $tampered;
    ok( !trusted(), "tampered cookie -> undef" );
}

note("tampered userid");
{
    my $other = temp_user();
    $other->update_self( { status => 'A' } );

    $req = FakeRequest->new;
    ( my $tampered = $cookie_value ) =~ s/^v1:u\d+:/"v1:u" . $other->id . ":"/e;
    $req->{jar}{ljtrust} = $tampered;
    ok( !trusted(), "resigned to a different userid -> undef (signature covers userid)" );
}

note("garbage cookie");
{
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = "total nonsense";
    ok( !trusted(), "garbage cookie -> undef" );
}

note("stale cookie is rejected even with a valid signature");
{
    # get_secret generates for old hour-aligned buckets in list context, so we
    # can forge a correctly-signed cookie from beyond the trust window
    my $old = time() - LJ::Session::TRUST_COOKIE_MAX_AGE() - 7200;
    $old -= $old % 3600;
    my ( $time, $secret ) = LJ::get_secret($old);
    ok( $secret, "generated a secret for an old time bucket" );

    my $sig = LJ::Session::trust_cookie_signature( $old, $u->id, $uniq );
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} =
        "v1:u" . $u->id . ":t$old:g$sig//" . LJ::eurl( $LJ::COOKIE_GEN || "" );
    ok( !trusted(), "correctly-signed but stale cookie -> undef" );
}

note("cookie generation rotation revokes trust");
{
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $cookie_value;
    local $LJ::COOKIE_GEN      = "newgen";
    local @LJ::COOKIE_GEN_OKAY = ();
    ok( !trusted(), "rotated \$LJ::COOKIE_GEN -> undef" );
}

note("standing is re-checked live");
{
    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $cookie_value;

    $u->set_statusvis('S');
    ok( !trusted(), "suspended account -> undef" );

    $u->set_statusvis('V');
    ok( trusted(), "restored account -> trusted again" );

    $u->update_self( { status => 'N' } );
    ok( !trusted(), "unvalidated email -> undef" );

    $u->update_self( { status => 'A' } );
    ok( trusted(), "revalidated email -> trusted again" );
}

note("update_master_cookie issues the trust cookie (login path)");
{
    $req = FakeRequest->new;
    my $sess = LJ::Session->create( $u, exptype => 'long' );
    ok( $sess, "created a real session" );
    $sess->update_master_cookie;

    my @set = $req->set_cookies('ljtrust');
    ok( scalar @set, "update_master_cookie also set ljtrust" );

    $req = FakeRequest->new;
    $req->{jar}{ljtrust} = $set[0]->{value};
    my $got = trusted();
    ok( $got && $got->equals($u), "login-issued cookie validates" );

    $sess->destroy;
}

note("logout leaves the trust cookie alone");
{
    $req = FakeRequest->new;
    LJ::Session->clear_master_cookie;
    ok( !$req->set_cookies('ljtrust'),               "clear_master_cookie does not touch ljtrust" );
    ok( scalar $req->set_cookies('ljmastersession'), "but it did clear the master session" );
}

done_testing();
