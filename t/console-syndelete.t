# t/console-syndelete.t
#
# Test LJ::Console syn_delete command (delete and undelete of feed accounts).
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

my $u    = temp_user();
my $feed = temp_feed();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# requires the syn_edit priv
is(
    $run->( "syn_delete " . $feed->user ),
    "error: You are not authorized to run this command.",
    "Command requires syn_edit priv."
);
$u->grant_priv("syn_edit");
$u = LJ::load_user( $u->user );

# can only operate on syndicated accounts
my $reguser = temp_user();
is(
    $run->( "syn_delete " . $reguser->user ),
    "error: Not a syndicated account",
    "Refuses non-syndicated accounts."
);

is(
    $run->( "syn_delete " . $feed->user . " bogus" ),
    "error: Invalid action: must be 'delete' or 'undelete'.",
    "Rejects an unknown action."
);

# undelete on a non-deleted feed should fail
is(
    $run->( "syn_delete " . $feed->user . " undelete" ),
    "error: Account is not deleted.",
    "Cannot undelete a feed that is not deleted."
);

# delete it
is(
    $run->( "syn_delete " . $feed->user ),
    "success: Feed account "
        . $feed->user
        . " marked as deleted; the syndication system will stop refreshing it.",
    "Deletes the feed."
);
$feed = LJ::load_user( $feed->user );
ok( $feed->is_deleted, "Feed account is now marked deleted." );

# deleting again should fail
is(
    $run->( "syn_delete " . $feed->user ),
    "error: Account is already deleted.",
    "Cannot delete an already-deleted feed."
);

# undelete it
is(
    $run->( "syn_delete " . $feed->user . " undelete" ),
    "success: Feed account "
        . $feed->user
        . " restored; the syndication system will resume refreshing it.",
    "Undeletes the feed."
);
$feed = LJ::load_user( $feed->user );
ok( $feed->is_visible, "Feed account is visible again." );

# undelete resets the schedule so syndication picks it back up
my $dbh = LJ::get_db_reader();
my ( $checknext, $failcount ) =
    $dbh->selectrow_array( "SELECT checknext, failcount FROM syndicated WHERE userid=?",
    undef, $feed->id );
is( $failcount, 0, "failcount reset on undelete." );
ok( defined $checknext, "checknext is set on undelete." );

# explicit 'delete' action works too
is(
    $run->( "syn_delete " . $feed->user . " delete" ),
    "success: Feed account "
        . $feed->user
        . " marked as deleted; the syndication system will stop refreshing it.",
    "Explicit 'delete' action works."
);
$feed = LJ::load_user( $feed->user );
ok( $feed->is_deleted, "Feed account deleted via explicit action." );
