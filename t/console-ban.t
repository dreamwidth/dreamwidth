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
my $comm = temp_comm();
my $comm2 = temp_comm();

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

$refresh->();
is($run->("ban_set " . $u2->user),
   "success: User " . $u2->user . " banned from " . $u->user);
is($run->("ban_set " . $u2->user . " from " . $comm->user),
   "error: You are not a maintainer of this account");

is(LJ::set_rel($comm, $u, 'A'), '1', "Set user as maintainer");
$refresh->();

is($run->("ban_set " . $u2->user . " from " . $comm->user),
   "success: User " . $u2->user . " banned from " . $comm->user);
is($run->("ban_list"),
   "info: " . $u2->user);
is($run->("ban_list from " . $comm->user),
   "info: " . $u2->user);
is($run->("ban_unset " . $u2->user),
   "success: User " . $u2->user . " unbanned from " . $u->user);
is($run->("ban_unset " . $u2->user . " from " . $comm->user),
   "success: User " . $u2->user . " unbanned from " . $comm->user);
is($run->("ban_list"),
   "info: " . $u->user . " has not banned any other users.");
is($run->("ban_list from " . $comm->user),
   "info: " . $comm->user . " has not banned any other users.");

is($run->("ban_list from " . $comm2->user),
   "error: You are not a maintainer of this account");
$u->grant_priv("finduser", "");
is($run->("ban_list from " . $comm2->user),
   "info: " . $comm2->user . " has not banned any other users.");
$u->revoke_priv("finduser", "");
