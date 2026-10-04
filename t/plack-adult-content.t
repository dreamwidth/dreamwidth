# Adult interstitial and cut-expansion regressions through the Plack stack.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.

use strict;
use warnings;
use Test::More;
use DateTime;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm with_fake_memcache);
use DW::Logic::AdultContent;
use LJ::Feed;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::DISABLED{adult_content} = 0;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'adultContentTest';
my $owner   = temp_user();
my $minor   = temp_user();
my $adult   = temp_user();
my $unknown = temp_user();
$minor->set_prop( init_bdate => DateTime->now->subtract( years => 17 )->ymd );
$adult->set_prop( init_bdate => DateTime->now->subtract( years => 18 )->ymd );
$adult->set_prop( hide_adult_content => 'explicit' );
my $entry = $owner->t_post_fake_entry( body => 'OUTSIDE_MARKER <cut>INSIDE_MARKER</cut>' );
$entry->set_prop( adult_content => 'explicit' );
$entry->slug('age-restriction-test');
my $date = substr( $entry->eventtime_mysql, 0, 10 );
$date =~ s!-!/!g;
my $name       = $owner->user;
my $eid        = $entry->ditemid;
my $reply_to   = $entry->t_enter_comment( u => $owner )->dtalkid;
my $base       = "http://localhost/users/$name";
my $logic      = 'DW::Logic::AdultContent';
my $comm       = temp_comm();
my $comm_entry = $owner->t_post_fake_entry( usejournal => $comm->user, usejournal_okay => 1 );
$comm_entry->set_prop( adult_content_maintainer => 'explicit' );

# Test DBs do not install S2 styles. Observe whether dispatch reaches rendering,
# while keeping the real routing, interstitial templates, auth, and RPC handlers.
my $renders = 0;
with_fake_memcache {
    no warnings 'redefine';
    local *LJ::make_journal = sub { $renders++; return 'JOURNAL_RENDERED'; };
    test_psgi $app, sub {
        my $cb       = shift;
        my $as_minor = 'as=' . $minor->user;
        for my $viewer ( $minor, $adult ) {
            my $res =
                $cb->(GET 'http://localhost/users/'
                    . $comm->user . '/'
                    . $comm_entry->ditemid
                    . '.html?as='
                    . $viewer->user );
            like(
                $res->content,
                qr/community administrators/,
                'maintainer-rated warning has a message'
            );
            unlike( $res->content, qr/JOURNAL_RENDERED/, 'maintainer rating is enforced' );
        }
        for my $path (
            "/$eid.html",                   "/$eid.html?style=site",
            "/$eid.html?format=light",      "/$eid.html?mode=reply",
            "/$eid.html?replyto=$reply_to", "/$date/age-restriction-test.html"
            )
        {
            my $before = $renders;
            my $res    = $cb->( GET $base. $path . ( $path =~ /\?/ ? '&' : '?' ) . $as_minor );
            is( $res->code, 200, 'blocked interstitial renders' );
            like( $res->content, qr/Restricted to 18\+/, "$path blocks known minor" );
            unlike( $res->content, qr/name="adult_check"/,
                'blocked page has no confirmation button' );
            is( $renders, $before, 'restricted request never reaches journal renderer' );
            like( $res->header('Cache-Control'),
                qr/no-cache/, 'interstitial is not shared-cacheable' );
        }
        my $hostname = $name;
        $hostname =~ s/_/-/g;
        for my $url ( "http://localhost/~$name/$eid.html", "http://$hostname.test.dw/$eid.html" ) {
            my $res = $cb->( GET "$url?$as_minor" );
            like( $res->content, qr/Restricted to 18\+/, 'alternate journal URL is also gated' );
        }

        # A logged-in viewer with no birthdate on file must still self-attest.
        my $res = $cb->( GET "$base/$eid.html?as=" . $unknown->user );
        like( $res->content, qr/Yes, I am at least 18 years old/, 'unknown age must self-attest' );
        unlike( $res->content, qr/JOURNAL_RENDERED/, 'unknown viewer has no entry body' );

        # A logged-out viewer gets the login gate: no confirm button, no self-
        # attestation, no body.
        $res = $cb->( GET "$base/$eid.html?as=nobody_exists" );
        like( $res->content, qr/Log In to View/, 'logged-out explicit entry shows login gate' );
        like( $res->content, qr/name=['"]password['"]/, 'login gate offers a login form' );
        unlike( $res->content, qr/name="adult_check"/, 'login gate has no confirmation button' );
        unlike(
            $res->content,
            qr/Yes, I am at least 18 years old/,
            'login gate does not offer self-attestation'
        );
        unlike( $res->content, qr/JOURNAL_RENDERED/, 'logged-out explicit entry has no body' );

        $res = $cb->( GET "$base/$eid.html?as=" . $owner->user );
        like( $res->content, qr/JOURNAL_RENDERED/, 'author exemption preserved' );

        $owner->set_prop( adult_content => 'explicit' );
        $entry->set_prop( adult_content => '' );
        for my $path ( '/', '/2026/', '/2026/01/', '/2026/01/01/', '/tag/', '/read', "/$eid.html" )
        {
            $res = $cb->( GET "$base$path?$as_minor" );
            like( $res->content, qr/Restricted to 18\+/, "journal restriction covers $path" );
        }
        $res = $cb->( GET "$base/?as=nobody_exists" );
        like( $res->content, qr/Log In to View/, 'logged-out explicit journal shows login gate' );
        unlike( $res->content, qr/JOURNAL_RENDERED/, 'logged-out explicit journal has no body' );
        for my $path ( '/data/rss', '/data/atom' ) {
            $res = $cb->( GET "$base$path?$as_minor" );
            like( $res->content, qr/JOURNAL_RENDERED/, "$path remains outside interstitial gate" );
        }
        $entry->set_prop( adult_content => 'none' );
        $res = $cb->( GET "$base/$eid.html?$as_minor" );
        like( $res->content, qr/JOURNAL_RENDERED/, 'entry can override journal default with none' );
        $entry->set_prop( adult_content => 'explicit' );

        my $rpc = "http://localhost/__rpc_cuttag?journal=$name&ditemid=$eid&cutid=1";
        for my $viewer ( $minor, $adult, $unknown, undef ) {
            my $as = $viewer ? 'as=' . $viewer->user : 'as=nobody_exists';
            $res = $cb->( GET "$rpc&$as" );
            is( $res->code, 403, 'cut RPC requires age eligibility and confirmation' );
            unlike( $res->content, qr/INSIDE_MARKER/, 'cut RPC does not leak body' );
        }
        $res = $cb->( GET "$rpc&as=" . $owner->user );
        like( $res->content, qr/INSIDE_MARKER/, 'author can expand own cut' );

        for my $viewer ( $minor, $adult, $unknown ) {
            my $as      = 'as=' . $viewer->user;
            my $form    = $cb->( GET "http://localhost/login?$as" );
            my ($token) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            ok( $token, 'received signed CSRF token' );
            $res = $cb->(
                POST "http://localhost/journal/adult_explicit?$as",
                Content => [
                    lj_form_auth => $token,
                    journalid    => $owner->id,
                    entryid      => $eid,
                    ret          => "$base/$eid.html"
                ]
            );
            if ( $viewer->equals($minor) ) {
                is( $res->code, 403, 'minor cannot POST approval directly' );
                ok(
                    !$logic->user_confirmed_page(
                        user          => $viewer,
                        journal       => $owner,
                        entry         => $entry,
                        adult_content => 'explicit'
                    ),
                    'no approval recorded for minor'
                );
            }
            else {
                is( $res->code, 303, 'eligible viewer confirmation redirects' );
                is( $res->header('Location'), "$base/$eid.html", 'confirmation returns to entry' );
                $res = $cb->( GET "$base/$eid.html?$as" );
                like( $res->content, qr/JOURNAL_RENDERED/, 'confirmed viewer reaches entry' );
                $res = $cb->( GET "$rpc&$as" );
                like( $res->content, qr/INSIDE_MARKER/, 'confirmed viewer can expand cut' );
            }
        }

        # A logged-out confirm POST for explicit content records nothing and
        # lands back on the login gate.
        {
            my $form = $cb->( GET "http://localhost/login?as=nobody_exists" );
            my ($token) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            $res = $cb->(
                POST "http://localhost/journal/adult_explicit?as=nobody_exists",
                Content => [
                    lj_form_auth => $token,
                    journalid    => $owner->id,
                    entryid      => $eid,
                    ret          => "$base/$eid.html"
                ]
            );
            is( $res->code, 303, 'logged-out explicit confirm redirects without recording' );
            $res = $cb->( GET "$base/$eid.html?as=nobody_exists" );
            like(
                $res->content,
                qr/Log In to View/,
                'logged-out explicit entry still gated after confirm POST'
            );
            unlike( $res->content, qr/JOURNAL_RENDERED/,
                'no entry body after logged-out confirm POST' );
        }

        # Even approvals created by an older deployment must not unblock a minor.
        LJ::MemCache::set(
            $logic->_memcache_key($minor),
            {
                explicit => { $owner->id => [$eid] }
            }
        );
        $res = $cb->( GET "$base/$eid.html?$as_minor" );
        like( $res->content, qr/Restricted to 18\+/, 'stale approval cannot bypass page gate' );
        $res = $cb->( GET "$rpc&$as_minor" );
        is( $res->code, 403, 'stale approval cannot bypass RPC gate' );

        $entry->set_prop( adult_content      => 'concepts' );
        $minor->set_prop( hide_adult_content => 'concepts' );
        $res = $cb->( GET "$base/$eid.html?$as_minor" );
        like(
            $res->content,
            qr/Yes, I want to view this content/,
            'minor may confirm discretion warning'
        );
        my ($token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        $res = $cb->(
            POST "http://localhost/journal/adult_concepts?$as_minor",
            Content => [
                lj_form_auth => $token,
                journalid    => $owner->id,
                entryid      => $eid,
                ret          => "$base/$eid.html"
            ]
        );
        is( $res->code, 303, 'minor discretion confirmation accepted' );
        $res = $cb->( GET "$base/$eid.html?$as_minor" );
        like( $res->content, qr/JOURNAL_RENDERED/, 'confirmed discretion entry renders' );

        # Logged-out discretion: confirming sets a site-wide cookie that unlocks
        # any concepts page; without it, the warning returns.
        $res = $cb->( GET "$base/$eid.html?as=nobody_exists" );
        like(
            $res->content,
            qr/Yes, I want to view this content/,
            'logged-out concepts shows discretion warning'
        );
        unlike( $res->content, qr/JOURNAL_RENDERED/, 'discretion warning hides the body' );
        my ($ctoken) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        $res = $cb->(
            POST "http://localhost/journal/adult_concepts?as=nobody_exists",
            Content => [
                lj_form_auth => $ctoken,
                journalid    => $owner->id,
                entryid      => $eid,
                ret          => "$base/$eid.html"
            ]
        );
        is( $res->code, 303, 'logged-out discretion confirmation redirects' );
        like( $res->header('Set-Cookie') || '',
            qr/adult_concepts_ok=1/, 'discretion confirmation sets the viewing cookie' );
        $res = $cb->( GET "$base/$eid.html?as=nobody_exists", Cookie => 'adult_concepts_ok=1' );
        like( $res->content, qr/JOURNAL_RENDERED/, 'concepts cookie unlocks the page' );
        $res = $cb->( GET "$base/$eid.html?as=nobody_exists" );
        like(
            $res->content,
            qr/Yes, I want to view this content/,
            'without the cookie the discretion warning returns'
        );

        $res = $cb->(
            POST "http://localhost/journal/adult_explicit?as=" . $adult->user,
            Content => [ journalid => $owner->id, entryid => 99999, ret => $base ]
        );
        unlike( $res->header('Location') || '',
            qr/\Q$base\E/, 'confirmation still requires CSRF token' );
    };
};

# Feeds: explicit content is account-gated, so anonymous readers get a login
# stub in place of the body; logged-in readers still receive the full entry.
{
    $entry->set_prop( adult_content => 'explicit' );
    my $r_feed = DW::Request::Standard->new( HTTP::Request->new( GET => "$base/data/atom" ) );

    my $opts = { pathextra => '/atom', saycharset => 'utf-8' };
    my $anon = LJ::Feed::make_feed( $r_feed, $owner, undef, {%$opts} );
    like( $anon, qr/Log in to read this entry/, 'anonymous feed stubs explicit entry' );
    unlike( $anon, qr/OUTSIDE_MARKER/, 'anonymous feed omits explicit body' );

    my $member = LJ::Feed::make_feed( $r_feed, $owner, $adult, {%$opts} );
    like( $member, qr/OUTSIDE_MARKER/, 'logged-in reader still receives explicit body' );
}
done_testing;
