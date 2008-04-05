# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
local $LJ::T_NO_COMMAND_PRINT = 1;

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("print one"),
   "info: Welcome to 'print'!\nsuccess: one");
is($run->("print one !two"),
   "info: Welcome to 'print'!\nsuccess: one\nerror: !two");
