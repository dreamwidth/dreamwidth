# -*-perl-*-
use strict;
use Test::More tests => 15;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Lang;
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("faqcat delete blah"),
   "error: You are not authorized to run this command.");

$u->grant_priv("faqcat");

is($run->("faqcat add blah blah 500"),
   "success: Category added/changed");
ok($run->("faqcat list") =~ /blah *500/,
   "Category created successfully!");

is($run->("faqcat add lizl lozl 501"),
   "success: Category added/changed");
ok($run->("faqcat list") =~ /lozl *501/,
   "Second category created successfully!");

is($run->("faqcat move lizl up"),
   "info: Category order changed.");
ok($run->("faqcat list") =~ /blah *501/,
   "Sort order swapped for first category.");
ok($run->("faqcat list") =~ /lozl *500/,
   "And for the second!");

is($run->("faqcat move lizl down"),
   "info: Category order changed.");
ok($run->("faqcat list") =~ /blah *500/,
   "Sort order swapped again for first category.");
ok($run->("faqcat list") =~ /lozl *501/,
   "And again for the second.");

is($run->("faqcat delete lizl"),
   "success: Category deleted");
ok($run->("faqcat list") !~ /lozl/,
   "One category deleted.");

is($run->("faqcat delete blah"),
   "success: Category deleted");
ok($run->("faqcat list") !~ /blah/,
   "Second category deleted.");
