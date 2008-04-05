# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user);

# check that it requires a login
my $u = temp_user();

is(LJ::check_priv($u, "supporthelp", "*"), 0, "Normal user doesn't have privs");

is($u->grant_priv("supporthelp", "*"), 1, "Granted user the priv");
is(LJ::check_priv($u, "supporthelp", "*"), 1, "User has priv");

is($u->revoke_priv("supporthelp", "*"), 1, "Revoked the priv from the user");
is(LJ::check_priv($u, "supporthelp", "*"), 0, "User no longer has the priv");
