# t/account-switcher.t
#
# Tests DW::AccountSwitcher: the on-site multi-account switcher. The active
# account stays in ljmastersession; the other signed-in accounts live in a
# separate "ljsessions" cookie as (userid, sessid, auth) handles. Covers cookie
# parsing, listing/validating stored accounts, switching (which re-validates
# against the DB and demotes the old active), promotion on logout, removal, and
# rejection of tampered / stale / rotated cookies.
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
use DW::AccountSwitcher;
use DW::Cache;

# Minimal fake request: a readable cookie jar plus a capture of everything the
# code under test sets via add_cookie.
package FakeRequest;

sub new { my ( $class, %a ) = @_; bless { jar => {}, set => [], %a }, $class }

sub cookie {
    my ( $self, $name ) = @_;
    return $self->{jar}{$name};
}
sub get_remote_ip { "127.0.0.1" }
sub header_in     { "" }

sub add_cookie {
    my ( $self, %args ) = @_;
    $self->{jar}{ $args{name} } = $args{delete} ? undef : $args{value};
    push @{ $self->{set} }, \%args;
}

sub set_cookies {
    my ( $self, $name ) = @_;
    return grep { $_->{name} eq $name } @{ $self->{set} };
}

sub last_cookie {
    my ( $self, $name ) = @_;
    my @set = $self->set_cookies($name);
    return @set ? $set[-1] : undef;
}

package main;

my $req;
no warnings 'redefine';
local *DW::Request::get = sub { $req };

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = "abcdefghij12345";

# Start a fresh simulated request: new jar, cleared per-request cache, optional
# incoming ljsessions cookie value.
sub new_request {
    my ($ljsessions) = @_;
    $req = FakeRequest->new;
    DW::Cache->request->clear_ns('account_switcher');
    $req->{jar}{ljsessions} = $ljsessions if defined $ljsessions;
    return $req;
}

# The active-account handle held by ljmastersession after a mutation.
sub master_userid {
    my $set = $req->last_cookie('ljmastersession') or return undef;
    return $1 if $set->{value} =~ /:u(\d+):/;
    return undef;
}

# Build an ljsessions cookie value from (u, sess) pairs, exactly as the module
# serializes it, so we can seed an incoming request.
sub build_cookie {
    my @pairs = @_;
    my $body  = join '|', 'v' . DW::AccountSwitcher::COOKIE_VER,
        map { "u$_->[0]->{userid}:s$_->[1]->{sessid}:a$_->[1]->{auth}" } @pairs;
    return $body . "//" . LJ::eurl( $LJ::COOKIE_GEN || "" );
}

# Make $u the active remote with a fresh long session.
sub login_active {
    my $u    = shift;
    my $sess = LJ::Session->create( $u, exptype => 'long' );
    $u->{_session} = $sess;
    LJ::set_remote($u);
    return $sess;
}

my $ua = temp_user();
my $ub = temp_user();
my $uc = temp_user();
$_->update_self( { status => 'A' } ) for ( $ua, $ub, $uc );

# ---------------------------------------------------------------------------
note("parsing: valid cookie lists the stored accounts");
{
    new_request();
    my $sb = LJ::Session->create( $ub, exptype => 'long' );
    my $sc = LJ::Session->create( $uc, exptype => 'long' );

    new_request( build_cookie( [ $ub, $sb ], [ $uc, $sc ] ) );
    login_active($ua);

    my @accts = DW::AccountSwitcher->accounts;
    is( scalar @accts, 2, "two stored accounts listed" );
    ok( ( grep  { $_->{userid} == $ub->id } @accts ), "account B present" );
    ok( ( grep  { $_->{userid} == $uc->id } @accts ), "account C present" );
    ok( ( !grep { $_->{userid} == $ua->id } @accts ), "active account A not listed" );
    ok( ( grep  { $_->{valid} } @accts ) == 2,        "both stored accounts validate" );
}

# ---------------------------------------------------------------------------
note("switch_to: promotes a stored account and demotes the old active");
{
    my $sb = LJ::Session->create( $ub, exptype => 'long' );
    my $sc = LJ::Session->create( $uc, exptype => 'long' );

    new_request( build_cookie( [ $ub, $sb ], [ $uc, $sc ] ) );
    login_active($ua);

    my $rv = DW::AccountSwitcher->switch_to( $ub->id );
    is( $rv,             1,       "switch_to returns 1 on success" );
    is( master_userid(), $ub->id, "ljmastersession now points at B" );
    ok( LJ::get_remote()->equals($ub), "remote is now B" );

    # ljsessions should now hold C (untouched) and A (demoted), but not B
    my @accts = DW::AccountSwitcher->accounts;      # dedupes active (B)
    my %ids   = map { $_->{userid} => 1 } @accts;
    ok( $ids{ $uc->id },  "C still stored" );
    ok( $ids{ $ua->id },  "old active A demoted into the list" );
    ok( !$ids{ $ub->id }, "B no longer in the stored list" );
}

# ---------------------------------------------------------------------------
note("switch_to: expired stored session is reported, not switched");
{
    my $sb     = LJ::Session->create( $ub, exptype => 'long' );
    my $cookie = build_cookie( [ $ub, $sb ] );
    $sb->destroy;                                   # session gone from the DB

    new_request($cookie);
    login_active($ua);

    my $rv = DW::AccountSwitcher->switch_to( $ub->id );
    is( $rv, 'expired', "switch_to reports 'expired' for a dead session" );
    ok( LJ::get_remote()->equals($ua), "active account unchanged" );

    # the account is still listed (for a pre-filled re-login) but flagged invalid
    my ($rec) = grep { $_->{userid} == $ub->id } DW::AccountSwitcher->accounts;
    ok( $rec && !$rec->{valid}, "expired account listed but not valid" );
}

# ---------------------------------------------------------------------------
note("switch_to: unknown account id is refused");
{
    new_request( build_cookie() );
    login_active($ua);
    is( DW::AccountSwitcher->switch_to( $ub->id ), 0, "not-stored account -> 0" );
}

# ---------------------------------------------------------------------------
note("promote_next: hands off to the first usable stored account");
{
    my $sb = LJ::Session->create( $ub, exptype => 'long' );
    my $sc = LJ::Session->create( $uc, exptype => 'long' );

    # simulate the active account having just been destroyed on logout
    new_request( build_cookie( [ $ub, $sb ], [ $uc, $sc ] ) );
    LJ::set_remote(undef);

    my $next = DW::AccountSwitcher->promote_next;
    ok( $next && $next->equals($ub), "promote_next returns B (first stored)" );
    is( master_userid(), $ub->id, "master cookie switched to B" );

    my %ids = map { $_->{userid} => 1 } DW::AccountSwitcher->accounts;
    ok( $ids{ $uc->id } && !$ids{ $ub->id }, "B removed from list, C remains" );
}

# ---------------------------------------------------------------------------
note("promote_next: nothing usable -> undef");
{
    my $sb     = LJ::Session->create( $ub, exptype => 'long' );
    my $cookie = build_cookie( [ $ub, $sb ] );
    $sb->destroy;

    new_request($cookie);
    LJ::set_remote(undef);
    ok( !defined DW::AccountSwitcher->promote_next, "no usable account -> undef" );
}

# ---------------------------------------------------------------------------
note("remove_account: destroys the session and drops it from the list");
{
    my $sb = LJ::Session->create( $ub, exptype => 'long' );
    my $sc = LJ::Session->create( $uc, exptype => 'long' );

    new_request( build_cookie( [ $ub, $sb ], [ $uc, $sc ] ) );
    login_active($ua);

    ok( DW::AccountSwitcher->remove_account( $uc->id ), "remove_account returns true" );
    ok( !LJ::Session->instance( $uc, $sc->{sessid} ), "C's session was destroyed" );

    my %ids = map { $_->{userid} => 1 } DW::AccountSwitcher->accounts;
    ok( $ids{ $ub->id } && !$ids{ $uc->id }, "C dropped, B remains" );
    ok( LJ::get_remote()->equals($ua),       "active account untouched" );
}

# ---------------------------------------------------------------------------
note("tampered auth token invalidates just that entry");
{
    my $sb = LJ::Session->create( $ub, exptype => 'long' );
    ( my $bad = build_cookie( [ $ub, $sb ] ) ) =~ s/(:a)(\w)/$1 . ($2 eq 'x' ? 'y' : 'x')/e;

    new_request($bad);
    login_active($ua);

    my ($rec) = grep { $_->{userid} == $ub->id } DW::AccountSwitcher->accounts;
    ok( $rec && !$rec->{valid}, "tampered auth -> account listed but invalid" );
    is(
        DW::AccountSwitcher->switch_to( $ub->id ),
        'expired',
        "cannot switch into a tampered entry"
    );
}

# ---------------------------------------------------------------------------
note("garbage cookie yields no accounts");
{
    new_request("total nonsense");
    login_active($ua);
    is( scalar DW::AccountSwitcher->accounts, 0, "garbage cookie -> empty list" );
}

# ---------------------------------------------------------------------------
note("cookie-generation rotation drops the stored accounts");
{
    my $sb = LJ::Session->create( $ub, exptype => 'long' );
    new_request( build_cookie( [ $ub, $sb ] ) );
    login_active($ua);

    local $LJ::COOKIE_GEN      = "newgen";
    local @LJ::COOKIE_GEN_OKAY = ();
    DW::Cache->request->clear_ns('account_switcher');    # re-read under the new gen
    is( scalar DW::AccountSwitcher->accounts, 0, "rotated cookie gen -> empty list" );
}

done_testing();
