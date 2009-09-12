# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
local $LJ::T_NO_COMMAND_PRINT = 1;

plan tests => 2;

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("print one"),
   "info: Welcome to 'print'!\nsuccess: one");
is($run->("print one !two"),
   "info: Welcome to 'print'!\nsuccess: one\nerror: !two");
