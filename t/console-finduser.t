# t/console-finduser.t
#
# Test LJ::Console finduser command.
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

use Test::More tests => 8;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("finduser " . $u->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("finduser");

$u->update_self( { email => $u->user . "\@$LJ::DOMAIN", status => 'A' } );
$u = LJ::load_user($u->user);

is($run->("finduser " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser user " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser email " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser userid " . $u->id),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser timeupdate " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw . "\n" .
   "info:   Last updated: Never");

is($run->("finduser timeupdate " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw . "\n" .
   "info:   Last updated: Never");

$u->revoke_priv("finduser");
