# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'sysban.pl';
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

plan tests => 6;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# -- SYSBAN ADD --

is($run->("sysban_add talk_ip_test 500.500.500.500 7 testing"),
   "error: You are not authorized to run this command.");

$u->grant_priv("sysban", "talk_ip_test");

ok(!LJ::sysban_check("talk_ip_test", "500.500.500.500"),
   "Not currently sysbanned");

my $msg = $run->("sysban_add talk_ip_test 500.500.500.500 7 testing");
my ($text, $banid) = split("#", $msg);
is($text, "success: Successfully created ban ",
   "Successfully created sysban");

# lame, but: sysban_check compares bandate to NOW();
sleep 2;

ok(LJ::sysban_check("talk_ip_test", "500.500.500.500"),
   "Successfully sysbanned");

is($run->("sysban_add talk_ip_test not-an-ip-address 7 testing"),
   "error: Format: xxx.xxx.xxx.xxx (ip address)");

is($run->("sysban_add ip 500.500.500.500 7 testing"),
   "error: You cannot create these ban types");

my $dbh = LJ::get_db_writer();
$dbh->do("DELETE FROM sysban WHERE banid = ?", undef, $banid);
