# t/console-changejournaltype.t
#
# Test LJ::Console change_journal_type command.
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
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;
local $LJ::T_SUPPRESS_EMAIL   = 1;

my $u  = temp_user();
my $u2 = temp_user();
$u->update_self(  { status => 'A' } );
$u2->update_self( { status => 'A' } );
$u2 = LJ::load_user( $u2->user );

my $comm = temp_comm();

my $commname = $comm->user;
my $owner    = $u2->user;
LJ::set_rel( $comm, $u, 'A' );
LJ::start_request();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# all of these should fail.
foreach my $to (qw(person community)) {
    is(
        $run->("change_journal_type $commname $to $owner"),
        "error: You are not authorized to run this command."
    );
}

### NOW CHECK WITH PRIVS
$u->grant_priv("changejournaltype");

{
    # test community maintainer case
    LJ::set_rel( $comm, $u2, 'A' );
    is( $run->("change_journal_type $owner community $u->{user}"),
        "error: Account administers 1 other communities, must remove maintainership first." );
    LJ::clear_rel( $comm, $u2, 'A' );
}

my $types = { 'community' => 'C', 'person' => 'P' };

foreach my $to (qw(person community)) {
    is(
        $run->("change_journal_type $commname $to $owner"),
        "success: User $commname converted to a $to account."
    );
    $comm = LJ::load_user( $comm->user );
    is( $comm->journaltype, $types->{$to}, "Converted to a $to" );

    if ( $comm->is_community ) {

        # have to check the database directly because convenience methods
        # know that communities aren't supposed to have passwords

        my $dbh  = LJ::get_db_writer() or die "Couldn't get db master";
        my $pass = $dbh->selectrow_array( q{SELECT password FROM password WHERE userid = ?},
            undef, $comm->userid ) // '';

        ok( $pass eq '', "community password is blank or not stored in password table" );
    }
}
