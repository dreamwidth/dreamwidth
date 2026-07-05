# t/captcha-trusted-anon.t
#
# Tests the trusted-anon captcha bypass: a logged-out browser vouched for by
# LJ::Session->trusted_anon_user gets the logged-in treatment from both captcha
# gates. Covers DW::Captcha::should_captcha_view (bypass at each would-show
# point, no fraud-counter side effects, dw.captcha.bypassed metric) and
# LJ::Talk::Post::require_captcha_test (anon-only checks bypassed, checks that
# also apply to logged-in users still enforced).
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
use DW::Captcha;
use LJ::Talk;

# Minimal fake request so we can drive the gates without a live stack.
package FakeRequest;
sub new { my ( $class, %a ) = @_; bless {%a}, $class }
sub uri           { $_[0]->{uri} }
sub query_string  { $_[0]->{query_string} }
sub get_remote_ip { $_[0]->{ip} }
sub host          { "www.example.com" }
sub header_in     { "" }
sub cookie        { undef }

package main;

my $req;
my $trusted = 0;
my @metrics;

# create test users before we mock DW::Request; user creation touches more of
# the request object than the gates under test do
my $journal = temp_user();
$journal->update_self( { status => 'A' } );
my $poster = temp_user();
$poster->update_self( { status => 'A' } );

no warnings 'redefine';
local *DW::Request::get             = sub { $req };
local *LJ::UniqCookie::current_uniq = sub { "testuniq" };
local *DW::Stats::increment         = sub { push @metrics, [@_] };

# The session side of trust is covered by t/session-trust.t; here we only care
# how the gates react, so stub the verdict.
local *LJ::Session::trusted_anon_user = sub { $trusted ? bless {}, 'LJ::User' : undef };

sub metric_count {
    my ( $name, $tag ) = @_;
    return scalar grep {
        $_->[0] eq $name
            && ( !$tag || grep { $_ eq $tag } @{ $_->[2] } )
    } @metrics;
}

# Force the captcha machinery on regardless of test config.
local %LJ::DISABLED                 = ( captcha => 0 );
local $LJ::CAPTCHA_HCAPTCHA_SITEKEY = "test-sitekey";
local $LJ::CAPTCHA_HCAPTCHA_SECRET  = "test-secret";

# regression: class-method site_enabled on the abstract base must reflect the
# configured implementation (broken by #3594, which made it always 0 and
# thereby disabled all comment captchas)
ok( DW::Captcha->site_enabled, "DW::Captcha->site_enabled true when hCaptcha is configured" );
{
    local $LJ::CAPTCHA_HCAPTCHA_SITEKEY = "";
    ok( !DW::Captcha->site_enabled, "and false when it is not" );
}

# Gate everyone (no IP matcher), deterministic fraud/refill config.
local $LJ::CAPTCHA_BYPASS_REGEX             = undef;
local $LJ::CAPTCHA_BYPASS_IP                = undef;
local $LJ::SHOULD_CAPTCHA_IP                = undef;
local $LJ::SHOULD_CAPTCHA_REQUEST           = undef;
local $LJ::CAPTCHA_FRAUD_INTERVAL_SECS      = 60;
local $LJ::CAPTCHA_FRAUD_LIMIT              = 1000;
local $LJ::CAPTCHA_FRAUD_FORGIVENESS_AMOUNT = 1;
local $LJ::CAPTCHA_FRAUD_SYSBAN_SECS        = 60;
local $LJ::CAPTCHA_RETEST_INTERVAL_SECS     = 3600;
local $LJ::CAPTCHA_REFILL_INTERVAL_SECS     = 60;
local $LJ::CAPTCHA_REFILL_AMOUNT            = 1;
local $LJ::CAPTCHA_MAX_REMAINING            = 10;

note("--- should_captcha_view ---");

LJ::Test::with_fake_memcache {

    # mckey is "uniq:ip/24"
    my $ip    = "198.51.100.7";
    my $mckey = "testuniq:198.51.100.0";
    $req = FakeRequest->new( uri => "/x", query_string => "", ip => $ip );

    note("no captcha record (first visit)");
    {
        $trusted = 0;
        @metrics = ();
        ok( DW::Captcha->should_captcha_view(undef), "untrusted anon, no record -> captcha" );
        ok( LJ::MemCache::get("cct:$ip"),            "untrusted visit feeds the fraud counter" );
    }

    LJ::MemCache::delete("cct:$ip");

    {
        $trusted = 1;
        @metrics = ();
        ok( !DW::Captcha->should_captcha_view(undef), "trusted anon, no record -> no captcha" );
        is( metric_count( 'dw.captcha.bypassed', 'reason:no_record' ),
            1, "bypass metric emitted with reason:no_record" );
        is( metric_count('dw.captcha.shown'), 0, "no shown metric" );
        ok( !LJ::MemCache::get("cct:$ip"), "trusted bypass does not feed the fraud counter" );
    }

    note("retest interval exceeded");
    {
        my $old = time() - $LJ::CAPTCHA_RETEST_INTERVAL_SECS - 10;
        LJ::MemCache::set( $mckey, join( ':', $old, $old, 5 ) );

        $trusted = 0;
        ok( DW::Captcha->should_captcha_view(undef), "untrusted -> captcha on retest" );

        $trusted = 1;
        @metrics = ();
        ok( !DW::Captcha->should_captcha_view(undef), "trusted -> no captcha on retest" );
        is( metric_count( 'dw.captcha.bypassed', 'reason:retest_interval' ),
            1, "bypass metric emitted with reason:retest_interval" );
    }

    note("out of requests");
    {
        LJ::MemCache::set( $mckey, join( ':', time(), time(), 0 ) );

        $trusted = 0;
        ok( DW::Captcha->should_captcha_view(undef), "untrusted -> captcha when out of requests" );

        $trusted = 1;
        @metrics = ();
        ok( !DW::Captcha->should_captcha_view(undef),
            "trusted -> no captcha when out of requests" );
        is( metric_count( 'dw.captcha.bypassed', 'reason:out_of_requests' ),
            1, "bypass metric emitted with reason:out_of_requests" );
    }

    note("logged-in short-circuits before the trust check");
    {
        $trusted = 1;
        @metrics = ();
        my $remote = bless { userid => 1 }, "LJ::User";
        ok( !DW::Captcha->should_captcha_view($remote), "logged-in -> no captcha" );
        is( metric_count('dw.captcha.bypassed'), 0, "and no bypass metric" );
    }
};

note("--- require_captcha_test ---");

# require_captcha_test only asks the entry for these two things
package FakeEntry;
sub ditemid      { 257 }
sub logtime_unix { time() }

package main;

my $entry = bless {}, 'FakeEntry';

# anonpost/authpost off: skip the rate/sysban DB paths, which are orthogonal
local %LJ::CAPTCHA_FOR = ();

my $check = sub {
    my (%opts) = @_;
    $trusted = $opts{trusted} ? 1 : 0;
    @metrics = ();
    return LJ::Talk::Post::require_captcha_test( $opts{commenter}, $journal, $opts{body} // "",
        $entry );
};

note("journal setting R (anonymous only)");
{
    $journal->set_prop( opt_show_captcha_to => 'R' );

    is( $check->( trusted => 0 ), 'journal_setting', "untrusted anon -> captcha" );

    is( $check->( trusted => 1 ), '', "trusted anon -> no captcha" );
    is( metric_count( 'dw.captcha.bypassed', 'reason:journal_setting' ),
        1, "bypass metric emitted with reason:journal_setting" );
    is( metric_count( 'dw.captcha.bypassed', 'type:hcaptcha' ),
        1, "bypass metric carries the implementation type tag" );

    is( $check->( trusted => 0, commenter => $poster ), '', "logged-in user -> no captcha" );
}

note("journal setting F (non-friends): trusted anon is still a non-friend");
{
    $journal->set_prop( opt_show_captcha_to => 'F' );
    is( $check->( trusted => 1 ), 'journal_setting', "trusted anon -> captcha" );
    is( metric_count('dw.captcha.bypassed'), 0, "no bypass metric" );
}

note("journal setting A (all): applies to logged-in users, so also to trusted anon");
{
    $journal->set_prop( opt_show_captcha_to => 'A' );
    is( $check->( trusted => 1 ), 'journal_setting', "trusted anon -> captcha" );
    is( $check->( trusted => 0, commenter => $poster ),
        'journal_setting', "logged-in user -> captcha too" );
}

my $spammy = "check out http://spam.example/ and also www.spam.example please";

note("comment_html_anon: anon-only content heuristics");
{
    $journal->set_prop( opt_show_captcha_to => 'N' );
    local %LJ::CAPTCHA_FOR = ( comment_html_anon => 1 );

    is( $check->( trusted => 0, body => $spammy ), 'comment_html', "untrusted anon -> captcha" );

    is( $check->( trusted => 1, body => $spammy ), '', "trusted anon -> no captcha" );
    is( metric_count( 'dw.captcha.bypassed', 'reason:comment_html' ),
        1, "bypass metric emitted with reason:comment_html" );

    is( $check->( trusted => 1, body => "hi, lovely post!" ),
        '', "clean body -> no captcha either way" );
    is( metric_count('dw.captcha.bypassed'), 0, "clean body records no bypass" );
}

note("comment_html_auth: applies to logged-in users, so also to trusted anon");
{
    local %LJ::CAPTCHA_FOR = ( comment_html_anon => 1, comment_html_auth => 1 );
    is( $check->( trusted => 1, body => $spammy ), 'comment_html', "trusted anon -> captcha" );
    is( metric_count('dw.captcha.bypassed'), 0, "no bypass metric" );
}

done_testing();
