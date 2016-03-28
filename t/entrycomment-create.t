# t/entrycomment-create.t
#
# Test entry/comment creation TODO
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

use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

my $u = temp_user();
ok($u, "got a user");

my $entry = $u->t_post_fake_entry;
ok($entry, "got entry");
my $c1 = $entry->t_enter_comment;
ok($c1, "got comment");
my $c2 = $c1->t_reply;
ok($c2, "got reply comment");

1;

