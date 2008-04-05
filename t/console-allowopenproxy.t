# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $dbh = LJ::get_db_writer();
my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("allow_open_proxy 127.0.0.1"),
   "error: You are not authorized to run this command.");
$u->grant_priv("allowopenproxy");
is($run->("allow_open_proxy 127.0.0.1"),
   "error: That IP address is not an open proxy.");
is($run->("allow_open_proxy 127001"),
   "error: That is an invalid IP address.");

$dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
         "127.0.0.1", "proxy", time(), "Marking as open proxy for test");
is(LJ::is_open_proxy("127.0.0.1"), 1,
   "Verified IP as open proxy.");
$dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
         "127.0.0.2", "proxy", time(), "Marking as open proxy for test");
is(LJ::is_open_proxy("127.0.0.2"), 1,
   "Verified IP as open proxy.");

is($run->("allow_open_proxy 127.0.0.1"),
   "success: 127.0.0.1 cleared as an open proxy for the next 24 hours");
is(LJ::is_open_proxy("127.0.0.1"), 0,
   "Verified IP has been cleared as open proxy.");

is($run->("allow_open_proxy 127.0.0.2 forever"),
   "success: 127.0.0.2 cleared as an open proxy forever");
is(LJ::is_open_proxy("127.0.0.2"), 0,
   "Verified IP has been cleared as open proxy.");

$dbh->do("DELETE FROM openproxy WHERE addr IN (?, ?)",
         undef, "127.0.0.1", "127.0.0.2");
$u->revoke_priv("allowopenproxy");
