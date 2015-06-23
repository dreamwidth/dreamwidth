# t/console-set.t
#
# Test LJ::Console set command.
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

LJ::set_remote($u);

# using a random userprop here, to test the console side of things
# rather than the setters themselves.

is($run->("set newpost_minsecurity friends"),
   "success: User property 'newpost_minsecurity' set to 'friends' for " . $u->user);
ok($u->prop("newpost_minsecurity") eq "friends", "Userprop set correctly for user.");

is($run->("set newpost_minsecurit friends"),
   "error: Unknown property 'newpost_minsecurit'");

is($run->("set for " . $comm->user . " newpost_minsecurity friends"),
   "error: You are not permitted to change this journal's settings.");

LJ::set_rel($comm, $u, 'A');
$refresh->();

is($run->("set for " . $comm->user . " newpost_minsecurity friends"),
   "success: User property 'newpost_minsecurity' set to 'friends' for " . $comm->user);
ok($comm->prop("newpost_minsecurity") eq "friends", "Userprop set correctly for community.");
