# t/plack-logged-out-timezone.t
#
# Test the logged-out timezone preference and journal cache policy.
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

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::S2;
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'TESTUNIQ1234567';

my $url            = 'http://localhost/manage/settings/?cat=display';
my $field          = 'LJ__Setting__TimeZone_timezone';
my $visitor_zone   = 'Asia/Tokyo';
my $account_zone   = 'America/New_York';
my $visitor_cookie = 'dw_timezone=Asia%2FTokyo';

sub timezone_cookie {
    my ($res) = @_;
    return ( grep { /^dw_timezone=/ } $res->header('Set-Cookie') )[0] // '';
}

sub selected_zone {
    my ($res)    = @_;
    my ($select) = $res->content =~ m{<select\b[^>]*\bname=["']\Q$field\E["'][^>]*>(.*?)</select>}s;
    return undef unless defined $select;
    my ($option) = grep { /\bselected\b/ } $select =~ /(<option\b[^>]*>)/g;
    return undef unless defined $option;
    my ($value) = $option =~ /\bvalue=["']([^"']*)["']/;
    return $value;
}

with_fake_memcache {
    my $viewer = temp_user();
    $viewer->set_prop( timezone => $account_zone );
    test_psgi $app, sub {
        my ($request) = @_;
        my $form = $request->( GET $url );
        is( $form->code,          200, 'anonymous display settings are accessible' );
        is( selected_zone($form), '',  'anonymous display settings show a blank timezone' );
        my ($auth) = $form->content =~ /name="lj_form_auth" value="([^"]+)"/;
        ok( $auth, 'the form provides a valid submission token' );

        my $saved =
            $request->( POST $url, Content => [ lj_form_auth => $auth, $field => $visitor_zone ] );
        is( $saved->code,          200,           'anonymous save succeeds' );
        is( selected_zone($saved), $visitor_zone, 'save response shows the selected timezone' );
        my $cookie = timezone_cookie($saved);
        like( $cookie, qr{^dw_timezone=Asia%2FTokyo;}, 'save sets the timezone cookie' );
        like( $cookie, qr{;\s*path=/(?:;|$)}i,         'the cookie is available outside settings' );
        like( $cookie, qr/;\s*HttpOnly\b/i,            'the cookie is HTTP-only' );
        like( $cookie, qr/;\s*SameSite=Lax\b/i,        'the cookie is SameSite=Lax' );
        like( $cookie, qr/;\s*secure\b/i, 'the cookie is Secure on the HTTPS test site' );
        like( $cookie, qr/;\s*domain=\.?test\.dw\b/i, 'the cookie reaches journal subdomains' );
        like( $cookie, qr/;\s*expires=/i,             'the cookie survives a browser restart' );

        is( selected_zone( $request->( GET $url, Cookie => $visitor_cookie ) ),
            $visitor_zone, 'the timezone cookie is read on subsequent visits' );
        is( selected_zone( $request->( GET $url, Cookie => 'dw_timezone=local' ) ),
            '', 'a noncanonical timezone cookie is ignored' );

        for my $value ( '0', 'local', 'US/Eastern', 'Asia/Tokyo ', "Asia/Tokyo\0extra" ) {
            my $invalid = $request->(
                POST $url,
                Cookie  => $visitor_cookie,
                Content => [ lj_form_auth => $auth, $field => $value ],
            );
            ok( $invalid->content =~ /invalid time zone/i,
                'invalid timezone is rejected: ' . unpack( 'H*', $value ) );
            is( timezone_cookie($invalid), '', 'invalid submission does not change the cookie' );
        }

        my $missing = $request->(
            POST $url,
            Cookie  => $visitor_cookie,
            Content => [ lj_form_auth => $auth ]
        );
        is( timezone_cookie($missing),
            '', 'a submission without the timezone leaves the cookie alone' );
        my $cleared = $request->(
            POST $url,
            Cookie  => $visitor_cookie,
            Content => [ lj_form_auth => $auth, $field => '' ]
        );
        is( selected_zone($cleared), '', 'clear response immediately shows the blank selection' );
        like(
            timezone_cookie($cleared),
            qr/^dw_timezone=;.*\bexpires=/i,
            'clear expires the cookie'
        );

        my $account_url  = $url . '&as=' . $viewer->user;
        my $account_form = $request->( GET $account_url, Cookie => $visitor_cookie );
        is( selected_zone($account_form),
            $account_zone, 'a signed-in viewer sees their own account setting' );
        my ($account_auth) = $account_form->content =~ /name="lj_form_auth" value="([^"]+)"/;
        my $account_saved = $request->(
            POST $account_url,
            Cookie  => $visitor_cookie,
            Content => [ lj_form_auth => $account_auth, $field => '' ],
        );
        is( timezone_cookie($account_saved),
            '', 'account settings do not overwrite the guest cookie' );
        is( selected_zone( $request->( GET $account_url, Cookie => $visitor_cookie ) ),
            '', 'the cleared account setting persists and does not fall back to the guest cookie' );
    };
};

with_fake_memcache {
    local $LJ::CAP_DEF{userdomain} = 1;
    my $owner     = temp_user();
    my $entry     = $owner->t_post_fake_entry();
    my $comment   = $entry->t_enter_comment( u => $owner )->dtalkid;
    my $journal   = 'http://localhost/users/' . $owner->user;
    my $entry_url = $journal . '/' . $entry->ditemid . '.html';

    no warnings 'redefine';
    local *LJ::S2::make_journal = sub {
        my ( undef, $style, $view, undef, $opts ) = @_;
        my $siteviews = $style eq 'siteviews';
        ${ $opts->{handle_with_siteviews_ref} } = $siteviews;
        return "<p>Fixture $view</p>";
    };

    test_psgi $app, sub {
        my ($request) = @_;
        for my $route (
            [ entry => $entry_url,      '' ],
            [ entry => $entry_url,      "thread=$comment" ],
            [ reply => $entry_url,      "replyto=$comment" ],
            [ read  => "$journal/read", '' ]
            )
        {
            my ( $view, $base, $query ) = @$route;
            for my $style ( '', 'style=site' ) {
                my $args = join '&', grep { length } ( $query, $style );
                my $page = length($args) ? "$base?$args" : $base;
                for my $cookie ( '', $visitor_cookie ) {
                    my $label = "$page, " . ( $cookie ? 'with a timezone' : 'without a timezone' );
                    my $res   = $request->( GET $page, ( $cookie ? ( Cookie => $cookie ) : () ) );
                    is( $res->code, 200, "$label renders successfully" );
                    if ($style) {
                        ok( $res->content =~ /<html\b.*Fixture \Q$view\E/s,
                            "$label uses the site wrapper" );
                    }
                    else {
                        ok( $res->content eq "<p>Fixture $view</p>", "$label uses journal HTML" );
                    }
                    is(
                        $res->header('Cache-Control'),
                        'private, no-cache',
                        "$label requires private revalidation"
                    );
                    is( $res->header('Vary'), 'Cookie', "$label varies by cookie" );
                }
            }
        }
    };
};

done_testing;
