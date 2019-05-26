# t/console-changejournalstatus.t
#
# Test LJ::Console change_journal_status command.
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

use Test::More tests => 9;

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

$u2->set_visible;    # so we know where we're starting
$u2 = LJ::load_user( $u2->user );    # reload this user

is(
    $run->( "change_journal_status " . $u2->user . " normal" ),
    "error: You are not authorized to run this command."
);
$u->grant_priv( "siteadmin", "users" );

is( $run->( "change_journal_status " . $u2->user . " suspended" ),
    "error: Invalid status. Consult the reference." );
is( $run->( "change_journal_status " . $u2->user . " normal" ),
    "error: Account is already in that state." );

is( $run->( "change_journal_status " . $u2->user . " locked" ),
    "success: Account has been marked as locked" );
ok( $u2->is_locked, "Verified account is locked" );

is( $run->( "change_journal_status " . $u2->user . " memorial" ),
    "success: Account has been marked as memorial" );
ok( $u2->is_memorial, "Verified account is memorial" );

is( $run->( "change_journal_status " . $u2->user . " normal" ),
    "success: Account has been marked as normal" );
ok( $u2->is_visible, "Verified account is normal" );
