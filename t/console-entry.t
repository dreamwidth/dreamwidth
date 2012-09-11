# -*-perl-*-
use strict;
use Test::More tests => 3;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $remote = temp_user();
my $u = temp_user();
LJ::set_remote($remote);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("entry delete url reason"),
   "error: You are not authorized to run this command.");

$remote->grant_priv("deletetalk");

my $entry = $u->t_post_fake_entry;
my $url = $entry->url;

is($run->("entry delete $url reason"),
   "success: Entry action taken.");

LJ::Entry->reset_singletons;

is($run->("entry delete $url reason"),
   "error: URL provided does not appear to link to a valid entry.");
