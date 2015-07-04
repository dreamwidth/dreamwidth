# t/console-entry.t
#
# Test LJ::Console entry command
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

use Test::More tests => 3;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $remote = temp_user();
my $u = temp_user();
LJ::set_remote($remote);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("entry delete url reason"),
   "error: You are not authorized to run this command.");

$remote->grant_priv("deletetalk");

my $entry = $u->t_post_fake_entry;
my $url = $entry->url;

is($run->("entry delete $url reason"),
   "success: Entry action taken.");

LJ::Entry->reset_singletons;

is($run->("entry delete $url reason"),
   "error: URL provided does not appear to link to a valid entry.");
