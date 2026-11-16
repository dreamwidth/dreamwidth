# t/entry-community-admin-access.t
#
# Community administrators can read and edit members-only entries in their
# communities without also being members, as they can private entries.
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
use DW::Request::Standard;
use LJ::Test qw(temp_user temp_comm with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $comm     = temp_comm();
my $admin    = temp_user();
my $member   = temp_user();
my $outsider = temp_user();
LJ::set_rel( $comm, $admin, 'A' );
$member->join_community( $comm, 1, 1 );

my $entry = $admin->t_post_fake_comm_entry(
    $comm,
    security => 'friends',
    body     => 'MEMBERS_ONLY_MARKER',
);
is( $entry->security,  'usemask', 'entry is members-only' );
is( $entry->allowmask, 1,         'entry is visible to members' );
ok( $admin->can_manage($comm), 'administrator manages the community' );
ok( !$admin->member_of($comm), 'administrator is not a member' );

ok( $entry->visible_to($admin),     'administrator can read the entry' );
ok( $entry->editable_by($admin),    'administrator can edit the entry' );
ok( $entry->visible_to($member),    'member can read the entry' );
ok( !$entry->editable_by($member),  'member cannot edit the entry' );
ok( !$entry->visible_to($outsider), 'outsider cannot read the entry' );

# This covers every members-only entry in the community, not only the administrator's own,
# and administering one community grants nothing in another.
my $member_entry = $member->t_post_fake_comm_entry(
    $comm,
    security => 'friends',
    body     => 'MEMBER_POST_MARKER',
);
ok( $member_entry->visible_to($admin),  "administrator can read a member's entry" );
ok( $member_entry->editable_by($admin), "administrator can manage a member's entry" );

my $other_comm  = temp_comm();
my $other_admin = temp_user();
LJ::set_rel( $other_comm, $other_admin, 'A' );
ok( !$entry->visible_to($other_admin),  "another community's administrator cannot read the entry" );
ok( !$entry->editable_by($other_admin), "another community's administrator cannot edit the entry" );

# A watched community's members-only entries reach the reading page.
for my $viewer ( $admin, $outsider ) {
    $viewer->add_edge( $comm, watch => { nonotify => 1 } );
}

sub on_reading_page {
    my ($viewer) = @_;
    my @items = $viewer->watch_items( remote => $viewer, itemshow => 10, skip => 0 );
    return scalar grep { $_->{journalid} == $comm->id && $_->{jitemid} == $entry->jitemid } @items;
}
is( on_reading_page($admin),    1, 'administrator sees the entry on the reading page' );
is( on_reading_page($outsider), 0, 'outsider does not see the entry on the reading page' );

my $comm_user = $comm->user;
my $ditemid   = $entry->ditemid;

# Test DBs do not install S2 styles; the stub marks where rendering would start.
with_fake_memcache {
    no warnings 'redefine';
    local *LJ::make_journal = sub { return 'JOURNAL_RENDERED' };

    test_psgi $app, sub {
        my $cb = shift;

        my $page = "http://localhost/users/$comm_user/$ditemid.html";
        my $res  = $cb->( GET "$page?as=" . $admin->user );
        is( $res->code, 200, 'administrator can open the entry page' );
        like( $res->content, qr/JOURNAL_RENDERED/, 'entry page renders for the administrator' );

        $res = $cb->( GET "$page?as=" . $outsider->user );
        is( $res->code, 404, 'outsider cannot open the entry page' );

        my $edit = "http://localhost/entry/$comm_user/$ditemid/edit";
        $res = $cb->( GET "$edit?as=" . $admin->user );
        is( $res->code, 200, 'administrator can open the edit page' );
        like( $res->content, qr/MEMBERS_ONLY_MARKER/, 'edit form holds the entry text' );
        unlike(
            $res->content,
            qr/Could not find selected journal entry/,
            'administrator does not get the missing-entry error'
        );

        $res = $cb->( GET "$edit?as=" . $outsider->user );
        like(
            $res->content,
            qr/Could not find selected journal entry/,
            'outsider gets the missing-entry error'
        );
        unlike( $res->content, qr/MEMBERS_ONLY_MARKER/, 'outsider does not see the entry text' );
    };
};

done_testing();
