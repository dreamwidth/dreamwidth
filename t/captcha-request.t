#!/usr/bin/perl
# t/captcha-request.t
#
# Tests the request-level captcha hook ($LJ::SHOULD_CAPTCHA_REQUEST) in
# DW::Captcha::should_captcha_view: a truthy request matcher forces a captcha
# regardless of source IP, while the logged-in / bypass short-circuits and the
# existing IP-range behavior are preserved.
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

use Test::More tests => 7;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test;
use DW::Captcha;

# Minimal fake request so we can drive should_captcha_view without a live stack.
package FakeRequest;
sub new { my ( $class, %a ) = @_; bless {%a}, $class }
sub uri           { $_[0]->{uri} }
sub query_string  { $_[0]->{query_string} }
sub get_remote_ip { $_[0]->{ip} }
sub cookie        { undef }                   # no ljtrust cookie -> no trusted-anon bypass

package main;

my $req;
no warnings 'redefine';
local *DW::Request::get             = sub { $req };
local *LJ::UniqCookie::current_uniq = sub { "testuniq" };

# Enable the captcha code path; restrict IP-based captcha to one fake "datacenter"
# range; deterministic fraud config so the offender path computes cleanly and
# never trips the tempban threshold during the test.
local $LJ::CAPTCHA_HCAPTCHA_SITEKEY         = "test-sitekey";
local $LJ::CAPTCHA_BYPASS_REGEX             = undef;
local $LJ::CAPTCHA_BYPASS_IP                = undef;
local $LJ::SHOULD_CAPTCHA_IP                = sub { $_[0] =~ /^203\.0\.113\./ };
local $LJ::CAPTCHA_FRAUD_INTERVAL_SECS      = 60;
local $LJ::CAPTCHA_FRAUD_LIMIT              = 1000;
local $LJ::CAPTCHA_FRAUD_FORGIVENESS_AMOUNT = 1;
local $LJ::CAPTCHA_FRAUD_SYSBAN_SECS        = 60;

# A matcher that inspects the request, to confirm the coderef is passed a usable
# DW::Request and its return value drives the gate.
my $flag_matcher = sub { ( $_[0]->query_string // "" ) =~ /(?:^|&)flagme=/ };

LJ::Test::with_fake_memcache {

    # Residential IP, no request matcher -> the IP gate blocks (no captcha).
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = undef;
        $req = FakeRequest->new( uri => "/x", query_string => "a=1", ip => "198.51.100.1" );
        ok( !DW::Captcha->should_captcha_view(undef),
            "residential IP + no request matcher -> no captcha (IP gate)" );
    }

    # Residential IP, matcher inspects request and fires -> bypasses IP gate.
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = $flag_matcher;
        $req = FakeRequest->new( uri => "/x", query_string => "flagme=1", ip => "198.51.100.2" );
        ok( DW::Captcha->should_captcha_view(undef),
            "matcher fires on its signal -> captcha (IP gate bypassed)" );
    }

    # Residential IP, matcher inspects request and does not fire -> IP gate applies.
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = $flag_matcher;
        $req = FakeRequest->new( uri => "/x", query_string => "other=1", ip => "198.51.100.3" );
        ok( !DW::Captcha->should_captcha_view(undef),
            "matcher does not fire -> no captcha (IP gate applies)" );
    }

    # Logged-in user is never captcha'd, even when the matcher would fire.
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = sub { 1 };
        $req = FakeRequest->new( uri => "/x", query_string => "flagme=1", ip => "198.51.100.4" );
        my $remote = bless { userid => 1 }, "LJ::User";
        ok(
            !DW::Captcha->should_captcha_view($remote),
            "logged-in -> no captcha even with matcher true"
        );
    }

    # /captcha path short-circuits before the matcher.
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = sub { 1 };
        $req = FakeRequest->new( uri => "/captcha", query_string => "", ip => "198.51.100.5" );
        ok( !DW::Captcha->should_captcha_view(undef), "/captcha path -> no captcha" );
    }

    # Bypass regex wins over the matcher (it is checked earlier).
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = sub { 1 };
        local $LJ::CAPTCHA_BYPASS_REGEX   = qr{^/allowed/};
        $req = FakeRequest->new( uri => "/allowed/x", query_string => "", ip => "198.51.100.6" );
        ok(
            !DW::Captcha->should_captcha_view(undef),
            "bypass regex -> no captcha even with matcher true"
        );
    }

    # Datacenter IP, no matcher -> existing IP-range behavior still captchas.
    {
        local $LJ::SHOULD_CAPTCHA_REQUEST = undef;
        $req = FakeRequest->new( uri => "/x", query_string => "", ip => "203.0.113.9" );
        ok( DW::Captcha->should_captcha_view(undef),
            "datacenter IP -> captcha (existing IP behavior preserved)" );
    }
};
