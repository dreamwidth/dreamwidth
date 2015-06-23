# t/console-reset.t
#
# Test LJ::Console reset command.
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
local $LJ::T_SUPPRESS_EMAIL = 1;

my $u = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_remote($u);

# ------ RESET EMAIL -------
is($run->("reset_email " . $u2->user . " resetemail\@$LJ::DOMAIN \"resetting email\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("reset_email");

is($run->("reset_email " . $u2->user . " resetemail\@$LJ::DOMAIN \"resetting email\""),
   "success: Email address for '" . $u2->user . "' reset.");
$u2 = LJ::load_user($u2->user);

is($u2->email_raw, "resetemail\@$LJ::DOMAIN", "Email reset correctly.");
is($u2->email_status, "T", "Email status set correctly.");

my $dbh = LJ::get_db_reader();
my $rv = $dbh->do("SELECT * FROM infohistory WHERE userid=? AND what='email'", undef, $u2->id);
ok($rv < 1, "Addresses wiped from infohistory.");

$u->revoke_priv("reset_email");


# ------ RESET PASSWORD --------

is($run->("reset_password " . $u2->user . " \"resetting password\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("reset_password");

my $oldpass = $u2->password;

is($run->("reset_password " . $u2->user . " \"resetting password\""),
   "success: Password reset for '" . $u2->user . "'.");
$u2 = LJ::load_user($u2->user);
ok($u2->password ne $oldpass, "Password changed successfully.");

$u->revoke_priv("reset_password");


# ------ EMAIL ALIASES ----------
my $user = $u2->user;
my $alias = $u2->site_email_alias;

is($run->("email_alias show $user"),
   "error: You are not authorized to run this command.");
$u->grant_priv("reset_email");

is($run->("email_alias show $user"),
   "error: $alias is not currently defined.");

is($run->("email_alias set $user testing\@example.com"),
   "success: Successfully set $alias => testing\@example.com");

is($run->("email_alias show $user"),
   "success: $alias aliases to testing\@example.com");

is($run->("email_alias delete $user"),
   "success: Successfully deleted $alias alias.");

is($run->("email_alias show $user"),
   "error: $alias is not currently defined.");

$u->revoke_priv("reset_email");
