# t/usermoves.t
#
# Test moving users between clusters
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

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Event;
use FindBin qw($Bin);

if (@LJ::CLUSTERS < 2) {
    plan skip_all => "Less than two clusters.";
    exit 0;
} else {
    plan tests => 4;
}

my $u = LJ::load_user("system");
ok($u, "got system user");
ok($u->{clusterid}, "on a clusterid ($u->{clusterid})");

my @others = grep { $u->{clusterid} != $_ } @LJ::CLUSTERS;
my $dest = shift @others;

$ENV{DW_TEST} = 1;
my $rv = system("$ENV{LJHOME}/bin/moveucluster.pl", "--ignorebit", "--destdel", "--verbose=0", "system", $dest);
ok(!$rv, "no errors moving to cluster $dest");

$u = LJ::load_user("system", "force");
is($u->{clusterid}, $dest, "user moved to cluster $dest");



