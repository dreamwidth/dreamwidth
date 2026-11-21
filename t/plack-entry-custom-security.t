# t/plack-entry-custom-security.t
#
# Test saving access filters through the entry form.
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

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryCustomSecurityTest';

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $first = $owner->create_trust_group( groupname => 'First filter' );
$owner->create_trust_group( groupname => 'Other filter' );
my $last = $owner->create_trust_group( groupname => 'Last filter' );
my $url  = 'http://localhost/entry/new?as=' . $owner->user;

with_fake_memcache {
    test_psgi $app, sub {
        my $request = shift;
        my $form    = $request->( GET $url );
        is( $form->code, 200, 'Entry form loads' );
        my ($token) = $form->content =~ /name=["']lj_form_auth["']\s+value=["']([^"']+)/;
        ok( $token, 'Rendered form contains an auth token' ) or return;

        my @fields = (
            lj_form_auth  => $token,
            security      => 'custom',
            'action:post' => 'Post',
        );

        my $empty = $request->( POST $url, [ @fields, event => 'Missing groups' ] );
        ok(
            $empty->content =~ /Choose at least one access group/i,
            'Custom without groups explains why it was not saved'
        );

        $request->(
            POST $url,
            [ @fields, event => 'Chosen groups', custom_bit => $first, custom_bit => $last ]
        );

        my @entries = $owner->recent_entries( filtered_for => $owner );
        is( scalar @entries, 1, 'Only the submission with selected filters saves' );
        my ($entry) = grep { $_->event_orig eq 'Chosen groups' } @entries;
        ok( $entry, 'Entry with selected filters was saved' ) or return;
        is( $entry->security, 'usemask', 'Entry uses custom security' );
        is(
            $entry->allowmask,
            ( 1 << $first ) | ( 1 << $last ),
            'Persisted mask includes both chosen groups and not the other group'
        );
    };
};

done_testing();
