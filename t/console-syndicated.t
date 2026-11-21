# t/console-syndicated.t
#
# Test LJ::Console syn_merge, syn_edit, syn_editurl commands.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 44;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_feed with_fake_memcache);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u     = temp_user();
my $feed1 = temp_feed();
my $feed2 = temp_feed();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is(
    $run->( "syn_editurl " . $feed1->user . " $LJ::SITEROOT" ),
    "error: You are not authorized to run this command."
);
is( $run->( "syn_merge " . $feed1->user . " to " . $feed2->user . " using $LJ::SITEROOT" ),
    "error: You are not authorized to run this command." );
$u->grant_priv("syn_edit");
$u = LJ::load_user( $u->user );

my $dbh = LJ::get_db_reader();
my $currurl =
    $dbh->selectrow_array( "SELECT synurl FROM syndicated WHERE userid=?", undef, $feed1->id );
is( $run->( "syn_editurl " . $feed1->user . " $LJ::SITEROOT/feed.rss" ),
    "success: URL for account " . $feed1->user . " changed: $currurl => $LJ::SITEROOT/feed.rss" );

$currurl =
    $dbh->selectrow_array( "SELECT synurl FROM syndicated WHERE userid=?", undef, $feed1->id );
is( $currurl, "$LJ::SITEROOT/feed.rss", "Feed URL updated correctly." );

is( $run->( "syn_editurl " . $feed2->user . " $LJ::SITEROOT/feed.rss" ),
    "error: URL for account " . $feed2->user . " not changed: URL in use by " . $feed1->user );

with_fake_memcache {
    my $u2 = temp_user();
    my $u3 = temp_user();

    # $u2 watches both feeds, with custom colors only on the one being merged away;
    # $u3 watches both feeds, with custom colors only on the one being kept
    my $color = sub { LJ::color_todb( $_[0] ) };
    $u->add_edge( $feed1,
        watch => { fgcolor => $color->('#0000ff'), bgcolor => $color->('#ffff00'), nonotify => 1 }
    );
    $u2->add_edge( $feed1,
        watch => { fgcolor => $color->('#ff0000'), bgcolor => $color->('#00ff00'), nonotify => 1 }
    );
    $u3->add_edge( $feed1, watch => { nonotify => 1 } );

    $u2->add_edge( $feed2, watch => { nonotify => 1 } );
    $u3->add_edge( $feed2,
        watch => { fgcolor => $color->('#123456'), bgcolor => $color->('#abcdef'), nonotify => 1 }
    );

    # Set up reading filters covering:
    # - $u watching only $feed1 (News has $feed1 + custom adultcontent + unrelated $u3;
    #   Unrelated has only $u3 and must not gain $feed2)
    # - $u2 watching both feeds (OnlyOld has $feed1 with custom adultcontent;
    #   Both has $feed1 with custom adultcontent and $feed2 with defaults;
    #   OnlyNew has only $feed2 with custom adultcontent)
    # - $u3 watching both feeds (Both has $feed1 with defaults and $feed2 with custom adultcontent)
    my $u_news_fid  = $u->create_content_filter( name => 'News' );
    my $u_unrel_fid = $u->create_content_filter( name => 'Unrelated' );
    my $u_news  = $u->content_filters( id => $u_news_fid );
    my $u_unrel = $u->content_filters( id => $u_unrel_fid );
    $u_news->add_row( userid => $feed1->id, adultcontent => 'sfw' );
    $u_news->add_row( userid => $u3->id );
    $u_unrel->add_row( userid => $u3->id );

    my $u2_only_old_fid = $u2->create_content_filter( name => 'OnlyOld' );
    my $u2_both_fid     = $u2->create_content_filter( name => 'Both' );
    my $u2_only_new_fid = $u2->create_content_filter( name => 'OnlyNew' );
    my $u2_only_old = $u2->content_filters( id => $u2_only_old_fid );
    my $u2_both     = $u2->content_filters( id => $u2_both_fid );
    my $u2_only_new = $u2->content_filters( id => $u2_only_new_fid );
    $u2_only_old->add_row( userid => $feed1->id, adultcontent => 'nonexplicit' );
    $u2_both->add_row( userid => $feed1->id, adultcontent => 'sfw' );
    $u2_both->add_row( userid => $feed2->id );
    $u2_only_new->add_row( userid => $feed2->id, adultcontent => 'nonexplicit' );

    my $u3_both_fid = $u3->create_content_filter( name => 'Both' );
    my $u3_both     = $u3->content_filters( id => $u3_both_fid );
    $u3_both->add_row( userid => $feed1->id );
    $u3_both->add_row( userid => $feed2->id, adultcontent => 'nonexplicit' );

    # Warm watch/trustmask caches before merging to verify cache invalidation
    ok( $u->watches($feed1),  '$u watches $feed1 before merge' );
    ok( !$u->watches($feed2), '$u does not watch $feed2 before merge' );

    my $oldlimit = $LJ::MAX_WT_EDGES_LOAD;
    $LJ::MAX_WT_EDGES_LOAD = 1;
    is(
        $run->(
            "syn_merge " . $feed1->user . " to " . $feed2->user . " using $LJ::SITEROOT/feed.rss#2"
        ),
        "error: Unable to merge feeds. Too many users are watching the feed '"
            . $feed1->user
            . "'. We only allow merges for feeds with at most $LJ::MAX_WT_EDGES_LOAD watchers."
    );

    $LJ::MAX_WT_EDGES_LOAD = $oldlimit;

    my ($pretend_ok) = LJ::Feed::merge_feed(
        from    => $feed1,
        to      => $feed2,
        url     => "$LJ::SITEROOT/feed.rss#2",
        pretend => 1,
    );
    ok( $pretend_ok,                            'Pretend merge succeeds' );
    ok( $u_news->contains_userid( $feed1->id ), 'Pretend merge leaves old feed in filter' );
    ok( !$u_news->contains_userid( $feed2->id ),
        'Pretend merge does not add surviving feed to filter' );

    is(
        $run->(
            "syn_merge " . $feed1->user . " to " . $feed2->user . " using $LJ::SITEROOT/feed.rss#2"
        ),
        "success: Merged "
            . $feed1->user . " to "
            . $feed2->user
            . " using URL: $LJ::SITEROOT/feed.rss#2."
    );
    $feed1 = LJ::load_user( $feed1->user );
    ok( $feed1->is_renamed, "Feed redirection set up correctly." );
    is( scalar $feed1->watched_by_userids, 0, "No watches remaining for " . $feed1->user );
    is( scalar $feed2->watched_by_userids, 3, "3 watchers for " . $feed2->user );

    my $colors_for_feed2 = sub {
        my $edge = $_[0]->watch_list->{ $feed2->id } || {};
        return [ $edge->{fgcolor}, $edge->{bgcolor} ];
    };
    is_deeply(
        $colors_for_feed2->($u),
        [ '#0000ff', '#ffff00' ],
        "Colors moved to the merged feed for a user who only watched the old feed."
    );
    is_deeply(
        $colors_for_feed2->($u2),
        [ '#ff0000', '#00ff00' ],
        "Colors kept for a user who watched both feeds and customized the old one."
    );
    is_deeply(
        $colors_for_feed2->($u3),
        [ '#123456', '#abcdef' ],
        "Colors kept for a user who watched both feeds and customized only the new one."
    );

    # Verify watch/trustmask caches were invalidated
    ok( !$u->watches($feed1), '$u no longer watches $feed1 after merge' );
    ok( $u->watches($feed2),  '$u watches $feed2 after merge' );

    # Verify reading filter memberships and per-feed filter settings migrated cleanly
    ok( !$u_news->contains_userid( $feed1->id ), '$u News filter no longer contains old feed' );
    ok( $u_news->contains_userid( $feed2->id ),  '$u News filter now contains surviving feed' );
    is( ( $u_news->data->{ $feed2->id } || {} )->{adultcontent},
        'sfw', '$u News filter kept custom adultcontent setting' );
    ok( $u_news->contains_userid( $u3->id ), '$u News filter kept unrelated member' );

    ok( !$u_unrel->contains_userid( $feed1->id ), '$u Unrelated filter has no old feed' );
    ok(
        !$u_unrel->contains_userid( $feed2->id ),
        '$u Unrelated filter did not gain surviving feed'
    );
    ok( $u_unrel->contains_userid( $u3->id ), '$u Unrelated filter kept unrelated member' );

    ok( !$u2_only_old->contains_userid( $feed1->id ), '$u2 OnlyOld filter removed old feed' );
    ok( $u2_only_old->contains_userid( $feed2->id ),  '$u2 OnlyOld filter gained surviving feed' );
    is( ( $u2_only_old->data->{ $feed2->id } || {} )->{adultcontent},
        'nonexplicit', '$u2 OnlyOld filter kept custom adultcontent from old feed' );

    ok( !$u2_both->contains_userid( $feed1->id ), '$u2 Both filter removed old feed' );
    ok( $u2_both->contains_userid( $feed2->id ),  '$u2 Both filter kept surviving feed' );
    is( ( $u2_both->data->{ $feed2->id } || {} )->{adultcontent},
        'sfw', '$u2 Both filter carried over custom adultcontent from old feed' );

    ok( !$u2_only_new->contains_userid( $feed1->id ), '$u2 OnlyNew filter has no old feed' );
    ok( $u2_only_new->contains_userid( $feed2->id ),  '$u2 OnlyNew filter kept surviving feed' );
    is( ( $u2_only_new->data->{ $feed2->id } || {} )->{adultcontent},
        'nonexplicit', '$u2 OnlyNew filter kept custom adultcontent on surviving feed' );

    ok( !$u3_both->contains_userid( $feed1->id ), '$u3 Both filter removed old feed' );
    ok( $u3_both->contains_userid( $feed2->id ),  '$u3 Both filter kept surviving feed' );
    is( ( $u3_both->data->{ $feed2->id } || {} )->{adultcontent},
        'nonexplicit', '$u3 Both filter kept custom adultcontent on surviving feed' );

    # Simulate a fresh request to confirm memcache (not only in-process cache) was updated
    LJ::start_request();
    my $u_fresh    = LJ::load_userid( $u->id );
    my $news_fresh = $u_fresh->content_filters( name => 'News' );
    ok( !$u_fresh->watches($feed1), 'Fresh request: $u no longer watches $feed1' );
    ok( $u_fresh->watches($feed2),  'Fresh request: $u watches $feed2' );
    ok(
        !$news_fresh->contains_userid( $feed1->id ),
        'Fresh request: News filter does not contain old feed'
    );
    ok(
        $news_fresh->contains_userid( $feed2->id ),
        'Fresh request: News filter contains surviving feed'
    );
    is( ( $news_fresh->data->{ $feed2->id } || {} )->{adultcontent},
        'sfw', 'Fresh request: News filter retains custom adultcontent' );
};
