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

use Test::More tests => 13;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_feed);
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

my $u2 = temp_user();
my $u3 = temp_user();

# $u2 watches both feeds, with custom colors only on the one being merged away;
# $u3 watches both feeds, with custom colors only on the one being kept
my $color = sub { LJ::color_todb( $_[0] ) };
$u->add_edge( $feed1,
    watch => { fgcolor => $color->('#0000ff'), bgcolor => $color->('#ffff00'), nonotify => 1 } );
$u2->add_edge( $feed1,
    watch => { fgcolor => $color->('#ff0000'), bgcolor => $color->('#00ff00'), nonotify => 1 } );
$u3->add_edge( $feed1, watch => { nonotify => 1 } );

$u2->add_edge( $feed2, watch => { nonotify => 1 } );
$u3->add_edge( $feed2,
    watch => { fgcolor => $color->('#123456'), bgcolor => $color->('#abcdef'), nonotify => 1 } );

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
