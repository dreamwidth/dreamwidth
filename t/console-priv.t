# t/console-priv.t
#
# Test LJ::Console priv and priv_package tests.
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

use Test::More tests => 24;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();
my $u3 = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("priv grant admin:* " . $u2->user),
   "error: You are not permitted to grant admin:*");
is($run->("priv_package list"),
   "error: You are not authorized to run this command.");
$u->grant_priv("admin", "supporthelp");

################ PRIV PACKAGES ######################
my $pkg = $u->user; # random pkg name just to ensure uniqueness across tests

is($run->("priv_package create $pkg"),
   "success: Package '$pkg' created.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:", "package is empty");
is($run->("priv_package remove $pkg supporthelp:bananas"),
   "error: Privilege does not exist in package.");
is($run->("priv_package add $pkg supporthelp:bananas"),
   "success: Privilege (supporthelp:bananas) added to package #$pkg.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:\ninfo:    supporthelp:bananas", "package populated");

########### PRIV GRANTING #####################
$u->grant_priv("admin", "supportread/bananas");

# one user, one priv
is($run->("priv grant supporthelp:test " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.");
ok($u2->has_priv( "supporthelp", "test" ), "has priv");

is($run->("priv revoke supporthelp:test " . $u2->user),
   "info: Denying: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.");
ok(!$u2->has_priv( "supporthelp", "test" ), "no longer privved");

is($run->("priv grant supporthelp:test,supporthelp:bananas " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.\n"
   . "info: Granting: 'supporthelp' with arg 'bananas' for user '" . $u2->user . "'.");
ok($u2->has_priv( "supporthelp", "test" ), "has priv");
ok($u2->has_priv( "supporthelp", "bananas" ), "has priv");

is($run->("priv revoke_all supporthelp " . $u2->user),
   "info: Denying: 'supporthelp' with all args for user '" . $u2->user . "'.");
ok(!$u2->has_priv( "supporthelp" ), "no longer has priv");

is($run->("priv revoke supporthelp " . $u2->user),
   "error: You must explicitly specify an empty argument when revoking a priv.\n"
    . "error: For example, specify 'revoke foo:', not 'revoke foo', to revoke 'foo' with no argument.");

is($run->("priv revoke_all supporthelp:foo " . $u2->user),
   "error: Do not explicitly specify priv arguments when using revoke_all.");

is($run->("priv grant #$pkg " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'bananas' for user '" . $u2->user . "'.");

is($run->("priv grant supporthelp:newpriv " . $u2->user . "," . $u3->user),
   "info: Granting: 'supporthelp' with arg 'newpriv' for user '" . $u2->user . "'.\n"
   . "info: Granting: 'supporthelp' with arg 'newpriv' for user '" . $u3->user . "'.");


### LAST OF THE PRIV PACKAGE TESTS

is($run->("priv_package remove $pkg supporthelp:bananas"),
   "success: Privilege (supporthelp:bananas) removed from package #$pkg.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:", "package is empty again");
is($run->("priv_package delete $pkg"),
   "success: Package '#$pkg' deleted.");
ok($run->("priv_package list") !~ $pkg, "Package no longer exists.");
