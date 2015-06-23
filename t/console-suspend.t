# t/console-suspend.t
#
# Test LJ::Console suspend command.
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

use Test::More tests => 14;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

$u2->set_email( $u2->user . "\@$LJ::DOMAIN" );
$u2->set_visible;
$u2 = LJ::load_user($u2->user);
LJ::set_remote($u);

is($run->("suspend " . $u2->user . " 'because'"),
   "error: You are not authorized to run this command.");

$u->grant_priv( "suspend", "openid" );
is($run->("suspend " . $u2->user . " 'because'"),
   "error: " . $u2->user . " is not an identity account.");
is($run->("suspend " . $u2->email_raw . " \"because\" confirm"),
   "error: You are not authorized to suspend by email address.");

$u->grant_priv( "suspend", "*" );
is($run->("suspend " . $u2->user . " \"because\""),
   "success: User '" . $u2->user . "' suspended.");
$u2 = LJ::load_user($u2->user);
ok($u2->is_suspended, "User indeed suspended.");

is($run->("suspend " . $u2->email_raw . " \"because\""),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info:    " . $u2->user . "\n"
   . "info: To actually confirm this action, please do this again:\n"
   . "info:    suspend " . $u2->email_raw . " \"because\" confirm");
is($run->("suspend " . $u2->email_raw . " \"because\" confirm"),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "error: " . $u2->user . " is already suspended.");

is($run->("unsuspend " . $u2->user . " \"because\""),
   "success: User '" . $u2->user . "' unsuspended.");
$u2 = LJ::load_user($u2->user);
ok(!$u2->is_suspended, "User is no longer suspended.");

is($run->("suspend " . $u2->user . " \"because\""),
   "success: User '" . $u2->user . "' suspended.");
$u2 = LJ::load_user($u2->user);
ok($u2->is_suspended, "User suspended again.");

is($run->("unsuspend " . $u2->email_raw . " \"because\""),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info:    " . $u2->user . "\n"
   . "info: To actually confirm this action, please do this again:\n"
   . "info:    unsuspend " . $u2->email_raw . " \"because\" confirm");
is($run->("unsuspend " . $u2->email_raw . " \"because\" confirm"),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "success: User '" . $u2->user . "' unsuspended.");
ok(!$u2->is_suspended, "User is no longer suspended.");



