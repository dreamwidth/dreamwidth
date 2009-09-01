# -*-perl-*-
use strict;
use Test::More tests => 14;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
BEGIN { $LJ::HOME = $ENV{LJHOME}; }
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $remote = temp_user();
my $u = temp_user();
LJ::set_remote($remote);

$u->clear_prop("opt_logcommentips");
my $entry = $u->t_post_fake_entry;
my $comment = $entry->t_enter_comment(u => $u, body => "this comment is apple cranberries");

my $run = sub {
    my $cmd = shift;
    LJ::Comment->reset_singletons;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("comment delete url reason"),
   "error: You are not authorized to run this command.");

$remote->grant_priv("deletetalk");

my $entry = $u->t_post_fake_entry;
my $comment = $entry->t_enter_comment(u => $u, body => "this comment is bananas");
my $url = $comment->url;

is($run->("comment screen $url reason"),
   "success: Comment action taken.");
is($run->("comment screen $url reason"),
   "error: Comment is already screened.");

is($run->("comment unscreen $url reason"),
   "success: Comment action taken.");
is($run->("comment unscreen $url reason"),
   "error: Comment is not screened.");

is($run->("comment freeze $url reason"),
   "success: Comment action taken.");
is($run->("comment freeze $url reason"),
   "error: Comment is already frozen.");

is($run->("comment unfreeze $url reason"),
   "success: Comment action taken.");
is($run->("comment unfreeze $url reason"),
   "error: Comment is not frozen.");

is($run->("comment delete $url reason"),
   "success: Comment action taken.");
is($run->("comment delete $url reason"),
   "error: Comment is already deleted, so no further action is possible.");

my $parent = $entry->t_enter_comment(u => $u, body => "this comment is bananas");
my $parenturl = $parent->url;
my $commenturl = $entry->t_enter_comment(u => $u, parent => $parent, body => "b-a-n-a-n-a-s")->url;

is($run->("comment delete_thread $parenturl reason"),
   "success: Comment action taken.");
is($run->("comment delete_thread $parenturl reason"),
   "error: Comment is already deleted, so no further action is possible.");
is($run->("comment delete_thread $commenturl reason"),
   "error: Comment is already deleted, so no further action is possible.");
