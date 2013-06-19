# t/console-allowopenproxy.t
#
# Test LJ::Console allowopenproxy command.
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

use Test::More tests => 9;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $dbh = LJ::get_db_writer();
my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("allow_open_proxy 127.0.0.1"),
   "error: You are not authorized to run this command.");
$u->grant_priv("allowopenproxy");
is($run->("allow_open_proxy 127.0.0.1"),
   "error: That IP address is not an open proxy.");
is($run->("allow_open_proxy 127001"),
   "error: That is an invalid IP address.");

$dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
         "127.0.0.1", "proxy", time(), "Marking as open proxy for test");
is(LJ::is_open_proxy("127.0.0.1"), 1,
   "Verified IP as open proxy.");
$dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
         "127.0.0.2", "proxy", time(), "Marking as open proxy for test");
is(LJ::is_open_proxy("127.0.0.2"), 1,
   "Verified IP as open proxy.");

is($run->("allow_open_proxy 127.0.0.1"),
   "success: 127.0.0.1 cleared as an open proxy for the next 24 hours");
is(LJ::is_open_proxy("127.0.0.1"), 0,
   "Verified IP has been cleared as open proxy.");

is($run->("allow_open_proxy 127.0.0.2 forever"),
   "success: 127.0.0.2 cleared as an open proxy forever");
is(LJ::is_open_proxy("127.0.0.2"), 0,
   "Verified IP has been cleared as open proxy.");

$dbh->do("DELETE FROM openproxy WHERE addr IN (?, ?)",
         undef, "127.0.0.1", "127.0.0.2");
$u->revoke_priv("allowopenproxy");
