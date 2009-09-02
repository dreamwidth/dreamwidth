# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
BEGIN { $LJ::HOME = $ENV{LJHOME}; }
use LJ::Console;
use LJ::Test qw (temp_user);

plan tests => 5;

# check that it requires a login
my $u = temp_user();

is($u->has_priv( "supporthelp", "*" ), 0, "Normal user doesn't have privs");

is($u->grant_priv("supporthelp", "*"), 1, "Granted user the priv");
is($u->has_priv( "supporthelp", "*" ), 1, "User has priv");

is($u->revoke_priv("supporthelp", "*"), 1, "Revoked the priv from the user");
is($u->has_priv( "supporthelp", "*" ), 0, "User no longer has the priv");
