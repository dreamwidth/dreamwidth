# t/plack-manage-circle-purged.t
#
# Bulk removal of purged accounts from Manage Circle.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'manageCirclePurgedTest';

my $path           = 'http://localhost/manage/circle/edit';
my $cleanup_button = qr/name=["']preview_purged["']/;
my $confirm_button = qr/name=["']remove_purged["']/;

sub form_token {
    my ($response) = @_;
    my ($token)    = $response->decoded_content =~ /name=["']lj_form_auth["']\s+value=["']([^"']+)/;
    return $token;
}

with_fake_memcache {
    my (
        $owner,    $stranger, $watch_only, $trust_only, $both,
        $incoming, $active,   $deleted,    $suspended
    ) = map { temp_user() } 1 .. 9;
    $_->update_self( { status => 'A' } )
        for (
        $owner,    $stranger, $watch_only, $trust_only, $both,
        $incoming, $active,   $deleted,    $suspended
        );
    my $quiet = { nonotify => 1 };
    $owner->add_edge( $watch_only, watch => $quiet ) or die 'Could not add watch-only fixture';
    $owner->add_edge( $trust_only, trust => $quiet ) or die 'Could not add trust-only fixture';
    $incoming->add_edge( $owner, watch => $quiet ) or die 'Could not add incoming fixture';
    for my $target ( $both, $active, $deleted, $suspended ) {
        $owner->add_edge( $target, watch => $quiet, trust => $quiet )
            or die 'Could not add watch and trust fixture';
    }
    $_->set_expunged
        or die 'Could not mark fixture purged'
        for ( $watch_only, $trust_only, $both, $incoming );
    $deleted->set_statusvis('D')   or die 'Could not mark fixture deleted';
    $suspended->set_statusvis('S') or die 'Could not mark fixture suspended';

    my $owner_url    = "$path?as=" . $owner->user;
    my $stranger_url = "$path?as=" . $stranger->user;
    my $purged_edges = sub {
        my $watch = $owner->watch_list( force_database => 1 );
        my $trust = $owner->trust_list( force_database => 1 );
        return [
            grep { $watch->{$_} || $trust->{$_} }
            map { $_->id } ( $watch_only, $trust_only, $both )
        ];
    };
    my $purged_ids = [ map { $_->id } ( $watch_only, $trust_only, $both ) ];

    test_psgi $app, sub {
        my ($request) = @_;
        my $page = $request->( GET $owner_url );
        is( $page->code, 200, 'Manage Circle loads' );
        like( $page->decoded_content, $cleanup_button, 'Outgoing purged edges show the button' );
        my $owner_token = form_token($page);
        ok( $owner_token, 'Manage Circle issues a form token' );

        my $stranger_page = $request->( GET $stranger_url );
        unlike( $stranger_page->decoded_content, $cleanup_button, 'An empty circle has no button' );

        $request->( GET "$owner_url&remove_purged=1" );
        my $csrf = $request->( POST $owner_url, [ remove_purged => 1 ] );
        like( $csrf->decoded_content, qr/Invalid form submission/i, 'Cleanup requires CSRF token' );

        my $anon = $request->( POST $path, [ remove_purged => 1, lj_form_auth => $owner_token ] );
        like( $anon->header('Location') // '', qr{/login\?}, 'Anonymous cleanup requires login' );

        my $unauthorized = $request->(
            POST "$stranger_url&authas=" . $owner->user,
            [ remove_purged => 1, lj_form_auth => form_token($stranger_page) ]
        );
        like(
            $unauthorized->decoded_content,
            qr/couldn't be authenticated/i,
            'Cleanup cannot act as another personal account'
        );

        $owner->set_statusvis('O') or die 'Could not mark owner read-only';
        my $read_only =
            $request->( POST $owner_url, [ remove_purged => 1, lj_form_auth => $owner_token ] );
        like( $read_only->decoded_content, qr/read-only/i, 'A read-only owner cannot clean up' );
        $owner->set_statusvis('V') or die 'Could not restore owner status';

        my $preview =
            $request->( POST $owner_url, [ preview_purged => 1, lj_form_auth => $owner_token ] );
        like( $preview->decoded_content, $confirm_button, 'Review shows a separate confirmation' );
        for my $target ( $watch_only, $trust_only, $both ) {
            like(
                $preview->decoded_content,
                qr/\b@{[ $target->user ]}\b/,
                'Review lists the purged account'
            );
        }
        is_deeply( $purged_edges->(), $purged_ids,
            'Rejected requests and preview remove no edges' );

        my $confirmed = $request->(
            POST $owner_url,
            [ remove_purged => 1, lj_form_auth => form_token($preview) // $owner_token ]
        );
        is( $confirmed->code, 303, 'Successful cleanup redirects to Manage Circle' );
        like(
            $confirmed->header('Location') // '',
            qr{/manage/circle/edit\z},
            'Redirect returns to the current Circle'
        );
        is_deeply( $purged_edges->(), [],
            'All outgoing watch and trust edges to purged accounts are gone' );

        my $watch = $owner->watch_list( force_database => 1 );
        my $trust = $owner->trust_list( force_database => 1 );
        for my $target ( $active, $deleted, $suspended ) {
            ok( $watch->{ $target->id } && $trust->{ $target->id },
                'Non-purged account keeps both edges (status ' . $target->statusvis . ')' );
        }
        ok(
            $incoming->watch_list( force_database => 1 )->{ $owner->id },
            'An incoming subscription from a purged account is not removed'
        );
        my $cleaned = $request->( GET $owner_url );
        unlike( $cleaned->decoded_content, $cleanup_button,
            'No button for an incoming-only purged edge' );
    };
};

done_testing();
