#!/usr/bin/perl
# t/plack-no-cache.t
#
# Pages whose forms carry a per-user form_auth token must tell shared caches
# not to store them, or one user's confirmation form could be served to
# another.
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

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# ?as= impersonation is dev-only.
local $LJ::IS_DEV_SERVER = 1;

my $owner = temp_user();
$owner->update_self( { status => 'A' } );

my $entry   = $owner->t_post_fake_entry;
my $comment = $entry->t_enter_comment( u => $owner );

my $user    = $owner->user;
my $dtalkid = $comment->dtalkid;

with_fake_memcache {
    test_psgi $app, sub {
        my $cb = shift;

        # Each page, viewed by the comment's journal owner, shows its form.
        for my $page (
            "/talkscreen?mode=screen&journal=$user&talkid=$dtalkid&as=$user",
            "/delcomment?journal=$user&id=$dtalkid&as=$user",
            "/mobile/post?as=$user",
            )
        {
            my $res = $cb->( GET "http://localhost$page" );

            is( $res->code, 200, "GET $page returns 200" );
            like( $res->content, qr/name=["']?lj_form_auth/, "GET $page shows a form_auth form" );
            like( $res->header('Cache-Control') // '',
                qr/no-cache/, "GET $page is marked no-cache" );
        }
    };
};

done_testing();
