# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
BEGIN { $LJ::HOME = $ENV{LJHOME}; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

plan skip_all => 'Fix this test!';

my $u = temp_user();
my $u2 = temp_user();
LJ::update_user($u2, { status => 'A' });
$u2 = LJ::load_user($u2->user);

my $comm = temp_comm();

my $commname = $comm->user;
my $owner = $u2->user;
LJ::set_rel($comm, $u, 'A');
LJ::start_request();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# all of these should fail.
foreach my $to (qw(person community)) {
    is($run->("change_journal_type $commname $to $owner"),
       "error: You are not authorized to run this command.");
}

### NOW CHECK WITH PRIVS
$u->grant_priv("changejournaltype");

my $types = { 'community' => 'C', 'person' => 'P' };

foreach my $to (qw(person community)) {
    is($run->("change_journal_type $commname $to $owner"),
       "success: User $commname converted to a $to account.");
    $comm = LJ::load_user($comm->user);
    is($comm->journaltype, $types->{$to}, "Converted to a $to");
}

### check that 'shared' is not a valid journaltype
is($run->("change_journal_type $commname shared $owner"),
   "error: Type argument must be 'person' or 'community'.");

