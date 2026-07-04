# t/console-suspenduserpic.t
#
# Test LJ::Console suspend_userpic / unsuspend_userpic commands.
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

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

my $file_contents = sub {
    my $file = shift;
    open( my $fh, $file ) or die $!;
    my $ct = do { local $/; <$fh> };
    return \$ct;
};

# Read state straight from the DB so a cached object doesn't mask the second
# transition (suspend then unsuspend).
my $pic_state = sub {
    my $picid = shift;
    return $u->selectrow_array( "SELECT state FROM userpic2 WHERE userid=? AND picid=?",
        undef, $u->userid, $picid );
};

my $upfile = "$ENV{LJHOME}/t/data/userpics/good.jpg";
die "No such file $upfile" unless -e $upfile;

my $up;
eval { $up = LJ::Userpic->create( $u, data => $file_contents->($upfile) ) };
if ($@) {
    plan skip_all => "Storage failure: $@";
    exit 0;
}
else {
    plan tests => 5;
}

is(
    $run->( "suspend_userpic " . $up->url . " DMCA complaint" ),
    "error: You are not authorized to run this command.",
    "suspend_userpic requires siteadmin:userpics."
);
$u->grant_priv( "siteadmin", "userpics" );

is(
    $run->( "suspend_userpic " . $up->url . " DMCA complaint" ),
    "success: Userpic '" . $up->id . "' for '" . $u->user . "' suspended.",
    "suspend_userpic succeeds."
);
is( $pic_state->( $up->id ), "S", "Userpic actually suspended." );

is(
    $run->( "unsuspend_userpic " . $up->url ),
    "success: Userpic '" . $up->id . "' for '" . $u->user . "' unsuspended.",
    "unsuspend_userpic succeeds."
);
is( $pic_state->( $up->id ), "N", "Userpic restored to normal." );
