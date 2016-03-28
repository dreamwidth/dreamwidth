# t/console-faqcat.t
#
# Test LJ::Console faqcat commands.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 15;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
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
