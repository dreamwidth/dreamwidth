# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_feed);
local $LJ::T_NO_COMMAND_PRINT = 1;

#plan tests => 7;
plan skip_all => 'Fix this test!';

my $u = temp_user();
my $feed1 = temp_feed();
my $feed2 = temp_feed();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};


is($run->("syn_editurl " . $feed1->user . " $LJ::SITEROOT"),
   "error: You are not authorized to run this command.");
is($run->("syn_merge " . $feed1->user . " to " . $feed2->user . " using $LJ::SITEROOT"),
   "error: You are not authorized to run this command.");
$u->grant_priv("syn_edit");
$u = LJ::load_user($u->user);

my $dbh = LJ::get_db_reader();
my $currurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?", undef, $feed1->id);
is($run->("syn_editurl " . $feed1->user . " $LJ::SITEROOT/feed.rss"),
   "success: URL for account " . $feed1->user . " changed: $currurl => $LJ::SITEROOT/feed.rss");

my $currurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?", undef, $feed1->id);
is($currurl, "$LJ::SITEROOT/feed.rss", "Feed URL updated correctly.");

is($run->("syn_editurl " . $feed2->user . " $LJ::SITEROOT/feed.rss"),
   "error: URL for account " . $feed2->user . " not changed: URL in use by " . $feed1->user);

is($run->("syn_merge " . $feed1->user . " to " . $feed2->user . " using $LJ::SITEROOT/feed.rss#2"),
   "success: Merged " . $feed1->user . " to " . $feed2->user . " using URL: $LJ::SITEROOT/feed.rss#2.");
$feed1 = LJ::load_user($feed1->user);
ok($feed1->is_renamed, "Feed redirection set up correctly.");
