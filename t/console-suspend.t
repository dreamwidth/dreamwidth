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

$u2->set_email( $u2->user . "\@$LJ::DOMAIN" );
$u2->set_visible;
$u2 = LJ::load_user($u2->user);
LJ::set_remote($u);

is($run->("suspend " . $u2->user . " 'because'"),
   "error: You are not authorized to run this command.");
$u->grant_priv("suspend");

is($run->("suspend " . $u2->user . " \"because\""),
   "info: User '" . $u2->user . "' suspended.");
$u2 = LJ::load_user($u2->user);
ok($u2->is_suspended, "User indeed suspended.");

is($run->("suspend " . $u2->email_raw . " \"because\""),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info:    " . $u2->user . "\n"
   . "info: To actually confirm this action, please do this again:\n"
   . "info:    suspend " . $u2->email_raw . " \"because\" confirm");
is($run->("suspend " . $u2->email_raw . " \"because\" confirm"),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "error: " . $u2->user . " is already suspended.");

is($run->("unsuspend " . $u2->user . " \"because\""),
   "info: User '" . $u2->user . "' unsuspended.");
$u2 = LJ::load_user($u2->user);
ok(!$u2->is_suspended, "User is no longer suspended.");

is($run->("suspend " . $u2->user . " \"because\""),
   "info: User '" . $u2->user . "' suspended.");
$u2 = LJ::load_user($u2->user);
ok($u2->is_suspended, "User suspended again.");

is($run->("unsuspend " . $u2->email_raw . " \"because\""),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info:    " . $u2->user . "\n"
   . "info: To actually confirm this action, please do this again:\n"
   . "info:    unsuspend " . $u2->email_raw . " \"because\" confirm");
is($run->("unsuspend " . $u2->email_raw . " \"because\" confirm"),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info: User '" . $u2->user . "' unsuspended.");
ok(!$u2->is_suspended, "User is no longer suspended.");



