# -*-perl-*-
use strict;
use Test::More tests => 9;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

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

LJ::clear_rel($comm, $u, 'A');
$refresh->();
ok( ! $u->can_manage( $comm ), "Verified that user is not maintainer" );

is($run->("change_community_admin " . $comm->user . " " . $u->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("communityxfer");

is($run->("change_community_admin " . $u2->user . " " . $u->user),
   "error: Given community doesn't exist or isn't a community.");
is($run->("change_community_admin " . $comm->user . " " . $comm2->user),
   "error: New owner doesn't exist or isn't a person account.");

$u->update_self( { status => 'T' } );
is($run->("change_community_admin " . $comm->user . " " . $u->user),
   "error: New owner's email address isn't validated.");

$u->update_self( { status => 'A' } );
is($run->("change_community_admin " . $comm->user . " " . $u->user),
   "success: Transferred maintainership of '" . $comm->user . "' to '" . $u->user . "'.");

$refresh->();
ok( $u->can_manage( $comm ), "Verified user is maintainer" );
ok( $u->email_raw eq $comm->email_raw, "Addresses match" );
ok(!$comm->password, "Password cleared");
$u->revoke_priv("communityxfer");
