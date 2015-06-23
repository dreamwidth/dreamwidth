# t/console-tags.t
#
# Test LJ::Console tag_display and tag_permissions commands.
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
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $comm = temp_comm();
my $comm2 = temp_comm();

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_rel($comm, $u, 'A');
LJ::clear_rel($comm2, $u, 'A');
$refresh->();

# ----------- TAG DISPLAY --------------------------
is($run->("tag_display tagtest 1"),
   "error: Error changing tag value. Please make sure the specified tag exists.");

LJ::Tags::create_usertag($u, "tagtest", { display => 1 });
is($run->("tag_display tagtest 1"),
   "success: Tag display value updated.");
is($run->("tag_display for " . $comm->user . " tagtest 1"),
   "error: Error changing tag value. Please make sure the specified tag exists.");

LJ::Tags::create_usertag($comm, "tagtest", { display => 1 });
is($run->("tag_display for " . $comm->user . " tagtest 1"),
   "success: Tag display value updated.");
is($run->("tag_display for " . $comm2->user . " tagtest 1"),
   "error: You cannot change tag display settings for " . $comm2->user);


# ----------- TAG PERMISSIONS -----------------------
$u->set_prop("opt_tagpermissions", undef);
is($run->("tag_permissions access access"), "success: Tag permissions updated for " . $u->user);

$u = LJ::load_user($u->user);
is($u->raw_prop("opt_tagpermissions"), "protected,protected", "Tag permissions set correctly.");
is($run->("tag_permissions members members"),
   "error: Levels must be one of: 'private', 'public', 'none', 'access' (for personal journals), 'members' (for communities), 'author_admin' (for communities only), or the name of a custom group.");
$comm->set_prop("opt_tagpermissions", undef);
is($run->("tag_permissions for " . $comm->user . " public members"),
   "success: Tag permissions updated for " . $comm->user);

$comm = LJ::load_user($comm->user);
is($comm->raw_prop("opt_tagpermissions"), "public,protected", "Tag permissions set correctly.");
is($run->("tag_permissions " . $comm->user . " members members"),
   "error: This command takes either two or four arguments. Consult the reference.");
is($run->("tag_permissions fo " . $comm->user . " members members"),
   "error: Invalid arguments. First argument must be 'for'");

is($run->("tag_permissions for " . $comm2->user . " members members"),
   "error: You cannot change tag permission settings for " . $comm2->user);
