# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
BEGIN { $LJ::HOME = $ENV{LJHOME}; }
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

#plan tests => 24;
plan skip_all => 'Fix this test!';

my $u = temp_user();
my $u2 = temp_user();
my $u3 = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("priv grant admin:* " . $u2->user),
   "error: You are not authorized to run this command.");
is($run->("priv_package list"),
   "error: You are not authorized to run this command.");
$u->grant_priv("admin", "supporthelp");

################ PRIV PACKAGES ######################
my $pkg = $u->user; # random pkg name just to ensure uniqueness across tests

is($run->("priv_package create $pkg"),
   "success: Package '$pkg' created.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:", "package is empty");
is($run->("priv_package remove $pkg supporthelp:bananas"),
   "error: Privilege does not exist in package.");
is($run->("priv_package add $pkg supporthelp:bananas"),
   "success: Privilege (supporthelp:bananas) added to package #$pkg.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:\ninfo:    supporthelp:bananas", "package populated");

########### PRIV GRANTING #####################
$u->grant_priv("admin", "supportread/bananas");

# one user, one priv
is($run->("priv grant supporthelp:test " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.");
ok($u2->has_priv( "supporthelp", "test" ), "has priv");

is($run->("priv revoke supporthelp:test " . $u2->user),
   "info: Denying: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.");
ok(!$u2->has_priv( "supporthelp", "test" ), "no longer privved");

is($run->("priv grant supporthelp:test,supporthelp:bananas " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.\n"
   . "info: Granting: 'supporthelp' with arg 'bananas' for user '" . $u2->user . "'.");
ok($u2->has_priv( "supporthelp", "test" ), "has priv");
ok($u2->has_priv( "supporthelp", "bananas" ), "has priv");

is($run->("priv revoke_all supporthelp " . $u2->user),
   "info: Denying: 'supporthelp' with all args for user '" . $u2->user . "'.");
ok(!$u2->has_priv( "supporthelp" ), "no longer has priv");

is($run->("priv revoke supporthelp " . $u2->user),
   "error: You must explicitly specify an empty argument when revoking a priv.\n"
    . "error: For example, specify 'revoke foo:', not 'revoke foo', to revoke 'foo' with no argument.");

is($run->("priv revoke_all supporthelp:foo " . $u2->user),
   "error: Do not explicitly specify priv arguments when using revoke_all.");

is($run->("priv grant #$pkg " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'bananas' for user '" . $u2->user . "'.");

is($run->("priv grant supporthelp:newpriv " . $u2->user . "," . $u3->user),
   "info: Granting: 'supporthelp' with arg 'newpriv' for user '" . $u2->user . "'.\n"
   . "info: Granting: 'supporthelp' with arg 'newpriv' for user '" . $u3->user . "'.");


### LAST OF THE PRIV PACKAGE TESTS

is($run->("priv_package remove $pkg supporthelp:bananas"),
   "success: Privilege (supporthelp:bananas) removed from package #$pkg.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:", "package is empty again");
is($run->("priv_package delete $pkg"),
   "success: Package '#$pkg' deleted.");
ok($run->("priv_package list") !~ $pkg, "Package no longer exists.");
