# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
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

# ----------- TAG DISPLAY --------------------------
is($run->("tag_display tagtest 1"),
   "error: Error changing tag value. Please make sure the specified tag exists.");
LJ::Tags::create_usertag($u, "tagtest", { display => 1 });
is($run->("tag_display tagtest 1"),
   "success: Tag display value updated.");

is($run->("tag_display for " . $comm->user . " tagtest 1"),
   "error: Error changing tag value. Please make sure the specified tag exists.");
LJ::Tags::create_usertag($comm, "tagtest", { display => 1 });
is($run->("tag_display for " . $comm->user . " tagtest 1"),
   "success: Tag display value updated.");

is($run->("tag_display for " . $comm2->user . " tagtest 1"),
   "error: You cannot change tag display settings for " . $comm2->user);


# ----------- TAG PERMISSIONS -----------------------
$u->set_prop("opt_tagpermissions", undef);
is($run->("tag_permissions friends friends"), "success: Tag permissions updated for " . $u->user);

$u = LJ::load_user($u->user);
is($u->raw_prop("opt_tagpermissions"), "friends,friends", "Tag permissions set correctly.");

is($run->("tag_permissions friend friend"),
   "error: Levels must be one of: 'private', 'public', 'friends', or the name of a friends group.");

$comm->set_prop("opt_tagpermissions", undef);
is($run->("tag_permissions for " . $comm->user . " friends friends"),
   "success: Tag permissions updated for " . $comm->user);

$comm = LJ::load_user($comm->user);
is($comm->raw_prop("opt_tagpermissions"), "friends,friends", "Tag permissions set correctly.");

is($run->("tag_permissions " . $comm->user . " friends friends"),
   "error: This command takes either two or four arguments. Consult the reference.");

is($run->("tag_permissions fo " . $comm->user . " friends friends"),
   "error: Invalid arguments. First argument must be 'for'");

is($run->("tag_permissions for " . $comm2->user . " friends friends"),
   "error: You cannot change tag permission settings for " . $comm2->user);
