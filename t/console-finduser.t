# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("finduser " . $u->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("finduser");

LJ::update_user($u, { 'email' => $u->user . "\@$LJ::DOMAIN", 'status' => 'A' });
$u = LJ::load_user($u->user);

is($run->("finduser " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser user " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser email " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser userid " . $u->id),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

is($run->("finduser timeupdate " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw . "\n" .
   "info:   Last updated: Never");

is($run->("finduser timeupdate " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw . "\n" .
   "info:   Last updated: Never");

$u->revoke_priv("finduser");
