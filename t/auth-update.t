#!/usr/bin/perl
#
# t/auth-update.t
#
# Regression tests for shared login and identity changes in the legacy entry editor.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use Plack::Test;
use URI;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless $app;
my $community = temp_comm();
my $original  = temp_user();
my $current   = temp_user();
$current->update_self( { status => 'A' } );
no warnings 'redefine';
test_psgi $app, sub {
    my $cb = shift;
    {
        local *LJ::get_remote = sub { undef };
        my $res = $cb->( GET '/update?usejournal=' . $community->user . '&subject=Keep%20this' );
        ok( $res->is_redirect, 'Anonymous legacy editor redirects to shared login' );
        my %login    = URI->new( $res->header('Location') )->query_form;
        my $returnto = URI->new( $login{returnto} );
        is( $returnto->path, '/update', 'Return destination is the legacy editor' );
        my %query = $returnto->query_form;
        is( $query{usejournal}, $community->user, 'Community selection survives sign-in redirect' );
        is( $query{subject}, 'Keep this', 'Other editor arguments survive sign-in redirect' );
    }
    {
        local *LJ::get_remote = sub { $current };
        my $res = $cb->(
            POST '/update',
            [
                lj_form_auth  => 'expired-original-session',
                poster_remote => $original->user,
                event         => 'Keep this draft with its original author.',
                subject       => 'Preserved draft',
                'action:post' => 1,
            ]
        );
        is( $res->code, 200, 'Account change renders draft again' );
        like(
            $res->content,
            qr/Your active account changed\. Switch back/,
            'Account mismatch explained despite expired CSRF token'
        );
        like(
            $res->content,
            qr/Keep this draft with its original author\./,
            'Draft body preserved'
        );
        like(
            $res->content,
            qr/name=['"]poster_remote['"][^>]*value=['"]\Q@{[$original->user]}\E['"]/,
            'Original author preserved'
        );
    }
    {
        my $saved = $original->t_post_fake_entry(
            subject  => 'Private saved subject must not leak',
            body     => 'Private saved body must not leak',
            security => 'private'
        );
        local *LJ::get_remote = sub { $current };
        my $path = '/entry/' . $original->user . '/' . $saved->ditemid . '/edit';
        my $res  = $cb->(
            POST $path,
            [
                lj_form_auth  => 'expired-original-session',
                poster_remote => $original->user,
                event         => 'Keep my submitted edit draft.',
                subject       => 'Submitted edit draft',
                'action:post' => 1
            ]
        );
        is( $res->code, 200, 'Existing-entry account mismatch preserves edit form' );
        like(
            $res->content,
            qr/Your active account changed/,
            'Edit form explains account mismatch'
        );
        like( $res->content, qr/Keep my submitted edit draft\./, 'Submitted edit body retained' );
        like(
            $res->content,
            qr/name=['"]poster_remote['"][^>]*value=['"]\Q@{[$original->user]}\E['"]/,
            'Edit retains original author'
        );
        unlike(
            $res->content,
            qr/Private saved (?:body|subject) must not leak/,
            'Mismatch response does not expose saved private entry'
        );
        my $fresh = LJ::Entry->new( $original, ditemid => $saved->ditemid );
        is(
            $fresh->event_raw,
            'Private saved body must not leak',
            'Mismatched edit never modifies saved entry'
        );
    }
};
done_testing();
