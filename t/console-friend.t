# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

$u->add_friend($u2); # known starting point
$u->remove_friend($u);

is($run->("friend remove " . $u2->user),
   "success: " . $u2->user . " removed from friends list.");
ok(!$u->is_friend($u2), "Removed from Friends list");

is($run->("friend add " . $u2->user),
   "success: " . $u2->user . " added as a friend.");
ok($u->is_friend($u2), "Removed from Friends list");

is($run->("friend add " . $u2->user . " fakefriendgroup"),
   "error: You don't have a group called 'fakefriendgroup'.\n" .
   "success: " . $u2->user . " added as a friend.");

is($run->("friend list"),
   "info: User            S T  Name\n" .
   "info: ----------------------------------------------------------\n" .
   "info: " . sprintf("%-15s %1s %1s  %s", $u2->user, "", "", $u2->name_raw));


