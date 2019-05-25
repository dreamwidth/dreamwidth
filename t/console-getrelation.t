# t/console-getrelation.t
#
# Test LJ::Console getmaintainer/getmoderator commands
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

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u    = temp_user();
my $comm = temp_comm();

LJ::set_rel( $comm, $u, 'A' );
LJ::set_rel( $comm, $u, 'M' );

LJ::start_request();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is(
    $run->( "get_maintainer " . $comm->user ),
    "error: You are not authorized to run this command."
);

$u->grant_priv("finduser");

# check the four lookup directions

ok( $run->( "get_maintainer " . $u->user ) =~ $comm->user );

ok( $run->( "get_maintainer " . $comm->user ) =~ $u->user );

ok( $run->( "get_moderator " . $u->user ) =~ $comm->user );

ok( $run->( "get_moderator " . $comm->user ) =~ $u->user );
