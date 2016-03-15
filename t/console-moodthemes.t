# t/console-moodthemes.t
#
# Test LJ::Console moodtheme* commands.
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

use Test::More tests => 23;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

### CREATING AND LISTING THEMES #######

# FIXME: make this neater.
ok($run->("moodtheme_list") =~ "Kanji Moods", "Got public theme");
ok($run->("moodtheme_list 1") =~ "18x18 /img/mood/kanji/crazy.gif", "Got a theme");

ok($run->("moodtheme_list") !~ "Your themes", "No logged-in stuff.");
LJ::set_remote($u);
ok($run->("moodtheme_list") =~ "Your themes", "Got logged-in stuff.");

is($run->( "moodtheme_create blahblah \"my stuff\""), "error: " .
   LJ::Lang::ml( '/manage/moodthemes.bml.error.cantcreatethemes' ) );
local $LJ::T_HAS_ALL_CAPS = 1;

my $resp = $run->("moodtheme_create blahblah \"my stuff\"");
$resp =~ /(\d+)$/;
my $themeid = $1; # we'll need this later
ok($resp =~ "success: Success. Your new mood theme ID is $themeid");

ok($run->("moodtheme_list") =~ "my stuff", "New theme is listed correctly.");


#### MARKING AS PUBLIC/NONPUBLIC #####

is($run->("moodtheme_public $themeid Y"),
   "error: You are not authorized to run this command.");
$u->grant_priv("moodthememanager");

is($run->("moodtheme_public $themeid Y"),
   "success: Theme #$themeid marked as public.");
is($run->("moodtheme_public $themeid Y"),
   "error: This theme is already marked as public.");
ok($run->("moodtheme_list") =~ /info:\s*Y\s*$themeid/,
   "Marked as public");

is($run->("moodtheme_public $themeid N"),
   "success: Theme #$themeid marked as not public.");
is($run->("moodtheme_public $themeid N"),
   "error: This theme is already marked as not public.");
ok($run->("moodtheme_list") =~ /info:\s*N\s*$themeid/,
   "No longer marked as public.");


## ADDING STUFF TO THEMES ###

is($run->("moodtheme_setpic 1 1 url 2 2"),
   "error: You do not own this mood theme.");

is($run->("moodtheme_setpic $themeid 1 http://this.is.a.url/ 2 2"),
   "success: Data inserted for theme #$themeid, mood #1.");

my $list = $run->("moodtheme_list $themeid");

ok($list =~ "http://this.is.a.url/", "URL saved");
ok($list =~ "aggravated", "Mood saved.");
ok($list =~ "2x 2", "Dimensions saved");

# test deletions.
is($run->("moodtheme_setpic $themeid 1 \"\" 2 2"),
   "success: Data deleted for theme #$themeid, mood #1.");
is($run->("moodtheme_setpic $themeid 1 url 0 2"),
   "success: Data deleted for theme #$themeid, mood #1.");
is($run->("moodtheme_setpic $themeid 1 url 2 0"),
   "success: Data deleted for theme #$themeid, mood #1.");

# the above all take the same code path, so we don't need to
# check each deletion individually.
$list = $run->("moodtheme_list $themeid");
ok($list !~ "aggravated", "Mood deleted.");
