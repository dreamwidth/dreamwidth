# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

plan skip_all => 'Fix this test!';

my $u = temp_user();
my $comm = temp_comm();

LJ::set_rel($comm, $u, 'A');
LJ::set_rel($comm, $u, 'M');

LJ::start_request();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("get_maintainer " . $comm->user),
   "error: You are not authorized to run this command.");

$u->grant_priv("finduser");

# check the four lookup directions

ok($run->("get_maintainer " . $u->user) =~ $comm->user);

ok($run->("get_maintainer " . $comm->user) =~ $u->user);

ok($run->("get_moderator " . $u->user) =~ $comm->user);

ok($run->("get_moderator " . $comm->user) =~ $u->user);
