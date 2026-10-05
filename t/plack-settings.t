#!/usr/bin/perl
#
# t/plack-settings.t
#
# Characterize settings hub form contracts.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTML::Form;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::SiteScheme;
use LJ::Test qw(temp_user);
plan skip_all => 'Settings integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'settingsMutationProbe';

sub settings_cookie {
    my ($user) = @_;
    my $session = LJ::Session->create( $user, nolog => 1 );
    return
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
}

sub settings_form {
    my ( $content, $url ) = @_;
    return
        grep { ( $_->attr('id') || '' ) eq 'settings_form' }
        HTML::Form->parse( $content, 'http://localhost' . $url );
}

my $display_url = '/manage/settings/?cat=display';

test_psgi $app, sub {
    my $send   = shift;
    my $u      = temp_user();
    my $other  = temp_user();
    my $cookie = settings_cookie($u);
    my $field  = 'LJ__Setting__SiteScheme_sitescheme';

    my $submit_scheme = sub {
        my ( $cookie, $value ) = @_;
        my $res = $send->( GET $display_url, Cookie => $cookie );
        my ($form) = settings_form( $res->content, $display_url );
        $form->value( $field, $value );
        my $req = $form->click;
        $req->uri( 'http://localhost' . $display_url );
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

SKIP: {
        my %scheme = map { $_->{scheme} => 1 } DW::SiteScheme->available;
        skip 'tropo-red and tropo-purple schemes are required', 6
            unless $scheme{'tropo-red'} && $scheme{'tropo-purple'};

        my $res = $submit_scheme->( $cookie, 'tropo-purple' );
        like(
            $res->content,
            qr/<body[^>]*class="tropo tropo-purple"/,
            'the save response itself uses the newly selected scheme'
        );
        like(
            join( "\n", $res->headers->header('Set-Cookie') ),
            qr/\bBMLschemepref=tropo-purple\b/,
            'non-default save sets the existing BMLschemepref cookie'
        );
        is( LJ::load_userid( $u->id, 1 )->prop('schemepref'),
            'tropo-purple', 'selected scheme persists' );

        $res = $submit_scheme->( "$cookie; BMLschemepref=tropo-purple", 'tropo-red' );
        like(
            $res->content,
            qr/<body[^>]*class="tropo tropo-red"/,
            'saving the default scheme switches the wrapper immediately'
        );
        like(
            join( "\n", $res->headers->header('Set-Cookie') ),
            qr/\bBMLschemepref=.*expires=/i,
            'saving the default scheme deletes the preference cookie'
        );
        is( LJ::load_userid( $u->id, 1 )->prop('schemepref'),
            'tropo-red', 'default scheme persists' );
    }

    my $res = $send->( GET $display_url, Cookie => $cookie );
    my ($form) = settings_form( $res->content, $display_url );
    $other->set_prop( timeformat_24 => 0 );
    $res = $send->(
        POST $display_url . '&authas=' . $other->user,
        Cookie  => $cookie,
        Content => [
            lj_form_auth                         => $form->value('lj_form_auth'),
            'DW__Setting__TimeFormat_timeformat' => 1
        ]
    );
    unlike( $res->content, qr/id=['"]settings_form/, 'valid-token unauthorized target denied' );
    is( LJ::load_userid( $other->id, 1 )->prop('timeformat_24') || 0, 0,
        'denied target unchanged' );
};

test_psgi $app, sub {
    my $send = shift;
    my $res  = $send->( GET $display_url . '&delete_subscription=1' );
    is( $res->code, 200, 'anonymous crafted delete confirmation request renders normally' );

    $res = $send->( GET $display_url );
    my ($form) = settings_form( $res->content, $display_url );
    ok( $form, 'anonymous display settings render a form' ) or return;
    $form->value( 'DW__Setting__MobileView_val', 1 );
    my $request = $form->click;
    $request->uri( 'http://localhost' . $display_url );
    $res = $send->($request);
    like( $res->header('Set-Cookie') || '',
        qr/no_mobile=1/, 'anonymous MobileView save sets cookie' );
    my @cookie_pairs = map { /^([^;]+)/ ? $1 : () } $res->headers->header('Set-Cookie');
    $res = $send->( GET $display_url, Cookie => join( '; ', @cookie_pairs ) );
    ($form) = settings_form( $res->content, $display_url );
    is( $form->value('DW__Setting__MobileView_val'),
        1, 'anonymous MobileView cookie survives a fresh request' );
};

test_psgi $app, sub {
    my $send   = shift;
    my $owner  = temp_user();
    my $viewer = temp_user();
    $viewer->grant_priv( 'canview', 'subscriptions' );
    my $legacy = $owner->subscribe(
        event   => 'AddedToCircle',
        journal => $owner,
        method  => 'Inbox',
        arg1    => 1
    );
    my $has_sub = sub {
        my ($id) = @_;
        return grep { $_->id == $id } LJ::load_userid( $owner->id, 1 )->subscriptions;
    };
    my $cookie = settings_cookie($owner);
    my $url    = '/manage/settings/?cat=notifications';

    my $legacy_delete_url = $url . '&deletesub_' . $legacy->id . '=1';
    my $res               = $send->( GET $legacy_delete_url, Cookie => $cookie );
    ok( $has_sub->( $legacy->id ), 'legacy deletesub GET does not delete the subscription' );
    my ($delete_form) = settings_form( $res->content, $legacy_delete_url );
    ok( $delete_form, 'legacy deletesub GET renders a confirmation form' ) or return;
    is( $delete_form->value('delete_subscription_id'),
        $legacy->id, 'confirmation binds the exact owned subscription id' );
    my $delete_req = $delete_form->click('delete_subscription_confirm');
    $delete_req->uri( 'http://localhost' . $url );
    $delete_req->header( Cookie => $cookie );
    $send->($delete_req);
    ok( !$has_sub->( $legacy->id ), 'confirmed POST deletes the subscription' );

    # A token from an unrelated page is valid for the session, so a rejection
    # here comes from the inspection guard rather than the CSRF check.
    my $protected =
        $owner->subscribe( event => 'JournalNewEntry', journalid => 0, method => 'Inbox' );
    $protected->_deactivate;
    my $viewer_cookie  = settings_cookie($viewer);
    my $viewer_display = $send->( GET $display_url, Cookie => $viewer_cookie );
    my ($viewer_form) = settings_form( $viewer_display->content, $display_url );
    my $forged_res = $send->(
        POST "$url&user=" . $owner->user,
        Cookie  => $viewer_cookie,
        Content => [ lj_form_auth => $viewer_form->value('lj_form_auth'), deleteinactive => 1 ]
    );
    like(
        $forged_res->content,
        qr/couldn.t be authenticated as the specified account/,
        'the forged POST is rejected by the inspection guard'
    );
    ok( $has_sub->( $protected->id ),
        'a privileged inspector cannot delete the owner\'s inactive subscriptions' );
};

done_testing;
