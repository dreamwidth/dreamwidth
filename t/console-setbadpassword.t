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
$u2->set_prop("badpassword", 0);

is($run->("set_badpassword " . $u2->user . " on \"bad password\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("suspend");

$u = LJ::load_user($u->user);

is($run->("set_badpassword " . $u2->user . " on \"bad password\""),
   "info: User marked as having a bad password.");
ok($u2->prop("badpassword"), "Badpassword prop set correctly.");

is($run->("set_badpassword " . $u2->user . " off \"removing bad password\""),
   "info: User no longer marked as having a bad password.");
ok(!$u2->prop("badpassword"), "Badpassword prop unset correctly.");
$u->revoke_priv("suspend");
