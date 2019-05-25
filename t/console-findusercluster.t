# t/console-findusercluster.t
#
# Test LJ::Console find_user_cluster command
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

my $u  = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_remote($u);

is(
    $run->( "find_user_cluster " . $u2->user ),
    "error: You are not authorized to run this command."
);
$u->grant_priv("supporthelp");
is(
    $run->( "find_user_cluster " . $u2->user ),
    "success: "
        . $u2->user
        . " is on the "
        . LJ::DB::get_cluster_description( $u2->{clusterid} )
        . " cluster"
);
$u->revoke_priv("supporthelp");

$u->grant_priv("supportviewscreened");
is(
    $run->( "find_user_cluster " . $u2->user ),
    "success: "
        . $u2->user
        . " is on the "
        . LJ::DB::get_cluster_description( $u2->{clusterid} )
        . " cluster"
);
$u->revoke_priv("supportviewscreened");
