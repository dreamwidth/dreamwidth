# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'communitylib.pl';
BEGIN { $LJ::HOME = $ENV{LJHOME}; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

plan skip_all => 'Fix this test!';

my $u = temp_user();
my $u2 = temp_user();
my $comm = temp_comm();
my $comm2 = temp_comm();

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_rel($comm, $u, 'A');
LJ::clear_rel($comm2, $u, 'A');
$refresh->();

is($run->("community " . $comm->user . " add " . $u->user),
   "error: Adding users to communities with the console is disabled.");
is($run->("community " . $comm2->user . " remove " . $u2->user),
   "error: You cannot remove users from this community.");

LJ::join_community($comm, $u2);
is($run->("community " . $comm->user . " remove " . $u2->user),
   "success: User " . $u2->user . " removed from " . $comm->user);
ok(!LJ::is_friend($comm, $u2), "User removed from community.");

# test case where user's removing themselves
LJ::join_community($comm2, $u);
is($run->("community " . $comm2->user . " remove " . $u->user),
   "success: User " . $u->user . " removed from " . $comm2->user);
ok(!LJ::is_friend($comm2, $u), "User removed self from community.");



### SHARED JOURNAL FUNCTIONS #####
my $shared = temp_user();
LJ::update_user($shared, { journaltype => 'S' });
$shared = LJ::load_user($shared->user);

is($run->("shared " . $shared->user . " remove " . $u2->user),
   "error: You don't have access to manage this shared journal.");

LJ::set_rel($shared, $u, 'A');
$refresh->();

is($run->("shared " . $shared->user . " remove " . $u2->user),
   "success: User " . $u2->user . " can no longer post in " . $shared->user . ".");

is($run->("shared " . $shared->user . " add " . $u->user),
   "success: User " . $u->user . " has been given posting access to " . $shared->user . ".");

is($run->("shared " . $shared->user . " add " . $u2->user),
   "success: User " . $u2->user . " has been sent a confirmation email, and will be able to post in "
   . $shared->user . " when they confirm this action.");

like($run->("shared " . $shared->user . " add " . $u2->user),
     qr/already invited to join/);
