# t/console-community.t
#
# Test LJ::Console commmunity command.
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
use LJ::Community;
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u     = temp_user();
my $u2    = temp_user();
my $comm  = temp_comm();
my $comm2 = temp_comm();

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_rel( $comm, $u, 'A' );
LJ::clear_rel( $comm2, $u, 'A' );
$refresh->();

is(
    $run->( "community " . $comm->user . " add " . $u->user ),
    "error: Adding users to communities with the console is disabled."
);
is(
    $run->( "community " . $comm2->user . " remove " . $u2->user ),
    "error: You cannot remove users from this community."
);

$u2->join_community($comm);
ok( $u2->member_of($comm), "User is currently member of community." );
is(
    $run->( "community " . $comm->user . " remove " . $u2->user ),
    "success: User " . $u2->user . " removed from " . $comm->user
);
delete $LJ::REQ_CACHE_REL{ $comm->userid . "-" . $u2->userid . "-E" };
ok( !$u2->member_of($comm), "User removed from community." );

# test case where user's removing themselves
$u->join_community($comm2);
ok( $u->member_of($comm2), "User is currently member of community." );
is(
    $run->( "community " . $comm2->user . " remove " . $u->user ),
    "success: User " . $u->user . " removed from " . $comm2->user
);
delete $LJ::REQ_CACHE_REL{ $comm2->userid . "-" . $u->userid . "-E" };
ok( !$u->member_of($comm2), "User removed self from community." );
