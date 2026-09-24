#!/usr/bin/perl
#
# t/journal-native-request.t
#
# Verify native journal request plumbing and control-strip request notes.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use DW::Controller::Journal;
use DW::Request::Plack;

sub journal_app {
    my ($user) = @_;
    return sub {
        my ($env) = @_;
        DW::Request->reset;
        my $r = DW::Request::Plack->new($env);
        $r->status(200);
        my $ret = DW::Controller::Journal->render(
            user => $user,
            uri  => $r->uri,
            args => $r->query_string,
        );
        $r->status($ret) if defined $ret && !ref $ret && $ret > 0;
        return $ret if ref $ret;
        return $r->res;
    };
}

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $entry = $u->t_post_fake_entry(
    subject => 'Native journal subject',
    event   => 'Native journal body',
);

no warnings 'redefine';
local *DW::Routing::call = sub { return undef };
local *LJ::get_cap       = sub { return $_[1] eq 'userdomain' ? 1 : 0 };

subtest 'journal rendering receives the active native request' => sub {
    my $calls = 0;
    local *LJ::make_journal = sub {
        my ( $user, $view, $remote, $opts ) = @_;
        $calls++;
        isa_ok( $opts->{r}, 'DW::Request::Plack' );
        is( $opts->{r}, DW::Request->get, 'renderer uses the controller request' );
        return '<p>Native journal render</p>';
    };
    test_psgi journal_app( $u->user ), sub {
        my $res = shift->( GET 'http://localhost/' );
        is( $res->code, 200, 'journal request succeeds' );
        like( $res->content, qr/Native journal render/, 'rendered body reaches the response' );
    };
    is( $calls, 1, 'journal renderer called once' );
};

subtest 'no_control_strip note reaches DW::Hooks::NavStrip via plain DW::Request::note' => sub {

    DW::Request->reset;
    my $r = DW::Request::Plack->new(
        { REQUEST_METHOD => 'GET', PATH_INFO => '/', 'psgi.url_scheme' => 'http' } );

    # Self-viewing-own-journal, with LJ::is_enabled forced on, makes
    # DW::Hooks::NavStrip.pm's show_control_strip hook (already registered
    # at module load, not a test double) return a truthy display mask by
    # default (LJ::User::Permissions::control_strip_display defaults to "all
    # options checked" with no explicit prop). This lets the "before" call
    # below be a meaningful sanity check, not a vacuous undef from unrelated
    # missing setup, so the "after" undef is provably caused by the note.
    LJ::set_remote($u);
    LJ::set_active_journal($u);
    local *LJ::is_enabled = sub { return $_[0] eq 'control_strip' ? 1 : 0; };

    ok( !$r->note('no_control_strip'), 'control-strip suppression note is initially unset' );
    ok( LJ::Hooks::run_hook('show_control_strip'),
        'control strip hook returns a truthy display mask before the note is set (sanity check)' );

    $r->note( 'no_control_strip', 1 );
    is( $r->note('no_control_strip'), 1, 'note round-trips through plain DW::Request::note' );
    is( LJ::Hooks::run_hook('show_control_strip'),
        undef, 'DW::Hooks::NavStrip suppresses the control strip once the note is set' );
};

done_testing;
