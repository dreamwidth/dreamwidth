# t/console-setbadpassword.t
#
# Test LJ::Console setbadpassword command.
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

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm temp_feed memcache_stress);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_remote($u);
$u2->set_prop("badpassword", 0);

is($run->("set_badpassword " . $u2->user . " on \"bad password\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("suspend");

$u = LJ::load_user($u->user);

is($run->("set_badpassword " . $u2->user . " on \"bad password\""),
   "info: User marked as having a bad password.");
ok($u2->prop("badpassword"), "Badpassword prop set correctly.");

is($run->("set_badpassword " . $u2->user . " off \"removing bad password\""),
   "info: User no longer marked as having a bad password.");
ok(!$u2->prop("badpassword"), "Badpassword prop unset correctly.");
$u->revoke_priv("suspend");
