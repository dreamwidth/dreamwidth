# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm temp_feed memcache_stress);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_remote($u);

is($run->("set_underage " . $u2->user . " on \"is underage\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("siteadmin", "underage");

$u = LJ::load_user($u->user);

is($run->("set_underage " . $u2->user . " on \"is underage\""),
   "success: User marked as underage.");
ok($u2->underage, "Badpassword prop set correctly.");

is($run->("set_underage " . $u2->user . " off \"removing bad password\""),
   "success: User no longer marked as underage.");
ok(!$u2->underage, "User is no longer marked as underage.");
$u->revoke_priv("siteadmin", "underage");
