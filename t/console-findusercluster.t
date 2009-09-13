# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_remote($u);

is($run->("find_user_cluster " . $u2->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("supporthelp");
is($run->("find_user_cluster " . $u2->user),
   "success: " . $u2->user . " is on the " . LJ::get_cluster_description($u2->{clusterid}, 0) . " cluster");
$u->revoke_priv("supporthelp");

$u->grant_priv("supportviewscreened");
is($run->("find_user_cluster " . $u2->user),
   "success: " . $u2->user . " is on the " . LJ::get_cluster_description($u2->{clusterid}, 0) . " cluster");
$u->revoke_priv("supportviewscreened");
