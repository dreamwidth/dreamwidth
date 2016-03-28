# t/directorysearch-extra.t
#
# Test user search with friends/friendsof and interests.
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
use LJ::Test;
use LJ::Directory::Search;
use LJ::ModuleCheck;
if (LJ::ModuleCheck->have("LJ::UserSearch")) {
    # plan tests => 9;
    plan skip_all => "User search without workers currently bitrotted";
} else {
    plan 'skip_all' => "Need LJ::UserSearch module.";
    exit 0;
}
use LJ::Directory::MajorRegion;
use LJ::Directory::PackedUserRecord;

local @LJ::GEARMAN_SERVERS = ();  # don't dispatch set requests.  all in-process.

my $u1 = temp_user();
my $u2 = temp_user();
my $usercount = $u2->userid;

# init the search system
my $inittime = time();
{
    print "Building userset...\n";
    LJ::UserSearch::reset_usermeta(8 * ($usercount + 1));
    for my $uid (0..$usercount) {
        my $lastupdate = $inittime - $usercount + $uid;
        my $buf = LJ::Directory::PackedUserRecord->new(
                                                       updatetime  => $lastupdate,
                                                       age         => 100 + $uid < 256 ? 100 + $uid : 1,
                                                       # scatter around USA:
                                                       regionid    => 1 + int($uid % 60),
                                                       # even amount of all:
                                                       journaltype => (("P","I","C","Y")[$uid % 4]),
                                                       )->packed;
        LJ::UserSearch::add_usermeta($buf, 8);
    }
}
# doing actual searches
memcache_stress(sub {
{
    my ($search, $res);

    $search = LJ::Directory::Search->new;
    ok($search, "made a search");

    # test friend/friendof searching
    {
        $u1->add_edge( $u2, watch => { nonotify => 1 } );
        $u2->add_edge( $u1, watch => { nonotify => 1 } );
        $u1->remove_edge( $u1, watch => { nonotify => 1 } );
        $u2->remove_edge( $u2, watch => { nonotify => 1 } );

        $search = LJ::Directory::Search->new;
        $search->add_constraint(LJ::Directory::Constraint::HasFriend->new(userid => $u2->userid));
        $res = $search->search_no_dispatch;
        is_deeply([$res->userids], [$u1->userid], "hasfriend correct");
    }

    # test interests
    {
        $u1->set_interests({}, ['chedda', 'gouda', 'mad cash', 'stax of lindenz']);
        $u2->set_interests({}, ['chedda', 'phat bank', 'yaper']);
        $search = LJ::Directory::Search->new;
        $search->add_constraint(LJ::Directory::Constraint::Interest->new(interest => 'chedda'));
        $res = $search->search_no_dispatch;
        ok((grep { $_ == $u1->userid } $res->userids) && (grep { $_ == $u2->userid } $res->userids), "interest search correct");
    }
}
});

__END__

# kde last week
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=kde&fr_user=&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100

# lists brad as friend:
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=&fr_user=brad&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100

# brad lists as friend:
loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=&age_max=&int_like=&fr_user=&fro_user=brad&opt_format=pics&opt_sort=ut&opt_pagesize=100

