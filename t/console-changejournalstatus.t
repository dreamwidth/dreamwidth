# -*-perl-*-
use strict;
use Test::More tests => 9;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
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

$u2->set_visible;                  # so we know where we're starting
$u2 = LJ::load_user($u2->user);    # reload this user

is($run->("change_journal_status " . $u2->user . " normal"),
   "error: You are not authorized to run this command.");
$u->grant_priv("siteadmin", "users");

is($run->("change_journal_status " . $u2->user . " suspended"),
   "error: Invalid status. Consult the reference.");
is($run->("change_journal_status " . $u2->user . " normal"),
   "error: Account is already in that state.");

is($run->("change_journal_status " . $u2->user . " locked"),
   "success: Account has been marked as locked");
ok($u2->is_locked, "Verified account is locked");

is($run->("change_journal_status " . $u2->user . " memorial"),
   "success: Account has been marked as memorial");
ok($u2->is_memorial, "Verified account is memorial");

is($run->("change_journal_status " . $u2->user . " normal"),
   "success: Account has been marked as normal");
ok($u2->is_visible, "Verified account is normal");
