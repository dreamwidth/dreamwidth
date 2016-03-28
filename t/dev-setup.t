# t/dev-setup.t
#
# Test TODO
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

if ($LJ::IS_DEV_SERVER) {
    plan 'no_plan';
} else {
    plan skip_all => "not a developer machine";
    exit 0;
}

my $clustered = ( scalar @LJ::CLUSTERS < 2 ) ? 0 : 1;

my $u = LJ::load_user("system");
ok( $u, "loaded system user" );

if ( $clustered ) {  # don't complain about nonclustered dev setups
    ok( $clustered, "have 2 or more clusters" );
    ok(scalar keys %LJ::DBINFO >= 3, "have 3 or more dbinfo config sections");
}

{
    my %have = ();
    foreach my $dbname (map { $_->{dbname} || 'livejournal' } values %LJ::DBINFO) {
        $have{$dbname}++;
    }
    ok(! scalar(grep { $_ != 1 } values %have), "non-unique databases in config");
}

my %seen_db;
while (my ($n, $inf) = each %LJ::DBINFO) {
    if ($n eq "master") {
        ok(1, "have a master section");
        next unless $clustered;
        my $user_on_master = 0;
        foreach my $cid (@LJ::CLUSTERS) {
            $user_on_master = 1 if
                $inf->{role}{"cluster$cid"};
        }
        ok(!$user_on_master, "you don't have a cluster configured on a master");
    }
}
