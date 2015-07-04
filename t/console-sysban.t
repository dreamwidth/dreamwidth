# t/console-sysban.t
#
# Test LJ::Console sysban_add command.
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

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# -- SYSBAN ADD --

is($run->("sysban_add talk_ip_test 500.500.500.500 7 testing"),
   "error: You are not authorized to run this command.");

$u->grant_priv("sysban", "talk_ip_test");

ok(!LJ::sysban_check("talk_ip_test", "500.500.500.500"),
   "Not currently sysbanned");

my $msg = $run->("sysban_add talk_ip_test 500.500.500.500 7 testing");
my ($text, $banid) = split("#", $msg);
is($text, "success: Successfully created ban ",
   "Successfully created sysban");

# lame, but: sysban_check compares bandate to NOW();
sleep 2;

ok(LJ::sysban_check("talk_ip_test", "500.500.500.500"),
   "Successfully sysbanned");

is($run->("sysban_add talk_ip_test not-an-ip-address 7 testing"),
   "error: Format: xxx.xxx.xxx.xxx (ip address)");

is($run->("sysban_add ip 500.500.500.500 7 testing"),
   "error: You cannot create these ban types");

my $dbh = LJ::get_db_writer();
$dbh->do("DELETE FROM sysban WHERE banid = ?", undef, $banid);
