# t/console-infohistory.t
#
# Test LJ::Console infohistory command.
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
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u  = temp_user();
my $u2 = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is( $run->( "infohistory " . $u2->user ), "error: You are not authorized to run this command." );
$u->grant_priv( "finduser", "infohistory" );

is( $run->( "infohistory " . $u2->user ), "error: No matches." );

# put something in there.
$u2->infohistory_add( 'email', $u2->email_raw, 'T' );

my $response = $run->( "infohistory " . $u2->user );
like( $response, qr/Changed email at \d{4}-\d{2}-\d{2}/, "Date recorded correctly." );
like( $response, qr/Old value of email was/,             "Infohistory 'what' recorded." );
ok( $response =~ $u2->email_raw, "Old value recorded." );
like( $response, qr/Other information recorded: T/, "Other information recorded." );
