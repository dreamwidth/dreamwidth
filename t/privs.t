# t/privs.t
#
# Test user privilege-related commands
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

use Test::More tests => 7;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user);

# check that it requires a login
my $u = temp_user();

is( $u->has_priv( "supporthelp", "*" ), 0, "Normal user doesn't have privs" );

is( $u->grant_priv( "supporthelp", "*" ), 1, "Granted user the priv" );
is( $u->has_priv( "supporthelp", "*" ), 1, "User has priv" );

is( $u->revoke_priv( "supporthelp", "*" ), 1, "Revoked the priv from the user" );
is( $u->has_priv( "supporthelp", "*" ), 0, "User no longer has the priv" );

my @privs = qw/ supporthelp supportclose /;

$u->grant_priv($_) foreach @privs;
$u->load_user_privs(@privs);
ok( $u->{'_priv'}->{$_}, "Bulk load of privs okay." ) foreach @privs;
