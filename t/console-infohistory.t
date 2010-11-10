# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

plan tests => 6;

my $u = temp_user();
my $u2 = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("infohistory " . $u2->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("finduser", "infohistory");

is($run->("infohistory " . $u2->user),
   "error: No matches.");

# put something in there.
$u2->infohistory_add( 'email', $u2->email_raw, 'T' );

my $response = $run->("infohistory " . $u2->user);
like($response, qr/Changed email at \d{4}-\d{2}-\d{2}/, "Date recorded correctly.");
like($response, qr/Old value of email was/, "Infohistory 'what' recorded.");
ok($response =~ $u2->email_raw, "Old value recorded.");
like($response, qr/Other information recorded: T/, "Other information recorded.");
