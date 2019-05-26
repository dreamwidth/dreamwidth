# t/console-comment.t
#
# Test LJ::Console comment command.
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

my $remote = temp_user();
my $u      = temp_user();
LJ::set_remote($remote);

$u->clear_prop("opt_logcommentips");
my $entry   = $u->t_post_fake_entry;
my $comment = $entry->t_enter_comment( u => $u, body => "this comment is apple cranberries" );
my $url;

my $run = sub {
    my $cmd = shift;
    LJ::Comment->reset_singletons;
    return LJ::Console->run_commands_text($cmd);
};

is( $run->("comment delete url reason"), "error: You are not authorized to run this command." );

$remote->grant_priv("deletetalk");

$entry   = $u->t_post_fake_entry;
$comment = $entry->t_enter_comment( u => $u, body => "this comment is bananas" );
$url     = $comment->url;

is( $run->("comment screen $url reason"), "success: Comment action taken." );
is( $run->("comment screen $url reason"), "error: Comment is already screened." );

is( $run->("comment unscreen $url reason"), "success: Comment action taken." );
is( $run->("comment unscreen $url reason"), "error: Comment is not screened." );

is( $run->("comment freeze $url reason"), "success: Comment action taken." );
is( $run->("comment freeze $url reason"), "error: Comment is already frozen." );

is( $run->("comment unfreeze $url reason"), "success: Comment action taken." );
is( $run->("comment unfreeze $url reason"), "error: Comment is not frozen." );

is( $run->("comment delete $url reason"), "success: Comment action taken." );
is( $run->("comment delete $url reason"),
    "error: Comment is already deleted, so no further action is possible." );

my $parent    = $entry->t_enter_comment( u => $u, body => "this comment is bananas" );
my $parenturl = $parent->url;
my $commenturl =
    $entry->t_enter_comment( u => $u, parent => $parent, body => "b-a-n-a-n-a-s" )->url;

is( $run->("comment delete_thread $parenturl reason"), "success: Comment action taken." );
is( $run->("comment delete_thread $parenturl reason"),
    "error: Comment is already deleted, so no further action is possible." );
is( $run->("comment delete_thread $commenturl reason"),
    "error: Comment is already deleted, so no further action is possible." );
