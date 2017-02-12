# t/directorysearch.t
#
# Test directory search.
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
    # plan tests => 71;
    plan skip_all => "User search without workers currently bitrotted";
} else {
    plan 'skip_all' => "Need LJ::UserSearch module.";
    exit 0;
}
use LJ::Directory::MajorRegion;
use LJ::Directory::PackedUserRecord;

local @LJ::GEARMAN_SERVERS = ();  # don't dispatch set requests.  all in-process.

my @args;

my $is = sub {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($name, $str, @good_cons) = @_;
    my %args = map { LJ::durl($_) } split(/[=&]/, $str);
    my @cons = sort { ref($a) cmp ref($b) } LJ::Directory::Constraint->constraints_from_formargs(\%args);
    is_deeply(\@cons, \@good_cons, $name);
};

$is->("US/Oregon",
      "loc_cn=US&loc_st=OR&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR'));

$is->("OR (without US)",
      "loc_cn=&loc_st=OR&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR'));

$is->("Oregon (without US)",
      "loc_cn=&loc_st=Oregon&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR'));

$is->("Russia",
      "loc_cn=RU&opt_sort=ut",
      LJ::Directory::Constraint::Location->new(country => 'RU'));

$is->("Age Range + last week",
      "loc_cn=&loc_st=&loc_ci=&ut_days=7&age_min=14&age_max=27&int_like=&fr_user=&fro_user=&opt_format=pics&opt_sort=ut&opt_pagesize=100",
      LJ::Directory::Constraint::Age->new(from => 14, to => 27),
      LJ::Directory::Constraint::UpdateTime->new(days => 7));

$is->("Interest",
      "int_like=lindenz&opt_sort=ut",
      LJ::Directory::Constraint::Interest->new(interest => 'lindenz'));

$is->("Has friend",
      "fr_user=system&opt_sort=ut",
      LJ::Directory::Constraint::HasFriend->new(user => 'system'));

$is->("Is friend of",
      "fro_user=system&opt_sort=ut",
      LJ::Directory::Constraint::FriendOf->new(user => 'system'));

$is->("Is a community",
      "journaltype=C&opt_sort=ut",
      LJ::Directory::Constraint::JournalType->new(journaltype => 'C'));

# serializing tests
{
    my ($con, $back, $str);
    $con = LJ::Directory::Constraint::Location->new(country => 'US', state => 'OR');
    is($con->serialize, "Location:country=US&state=OR", "serializes");
    $con = LJ::Directory::Constraint::Location->new(country => 'US', state => '');
    $str = $con->serialize;
    is($str, "Location:country=US", "serializes");
    $back = LJ::Directory::Constraint->deserialize($str);
    ok($back, "went back");
    is(ref $back, ref $con, "same type");
}

my $usercount = 100;

# init the search system
my $inittime = time();
{
    LJ::UserSearch::reset_usermeta(8 * ($usercount + 1));
    for my $uid (0..$usercount) {
        my $lastupdate = $inittime - $usercount + $uid;
        my $buf = LJ::Directory::PackedUserRecord->new(
                                                       updatetime  => $lastupdate,
                                                       age         => $uid,
                                                       # scatter around USA:
                                                       regionid    => 1 + int($uid % 60),
                                                       # even amount of all:
                                                       journaltype => (("P","I","C","Y")[$uid % 4]),
                                                       )->packed;
        LJ::UserSearch::add_usermeta($buf, 8);
    }
}

# Major Region stuff (location canonicalization as well, for some major regions)
{
    local $LJ::_T_DEFAULT_MAJREGIONS = 1;
    my ($regid, $regname);
    $regid = LJ::Directory::MajorRegion->region_id("RU", "Somewhere", "Msk");
    is($regid, 64, "found matching region id for Msk");
    $regid = LJ::Directory::MajorRegion->region_id("RU", "Somewhere", "Blahblahblah");
    ok(!$regid, "didn't find blahblahblah");

    $regid = LJ::Directory::MajorRegion->region_id("RU", "", "");
    is($regid, 63, "found Russia");

    $regid = LJ::Directory::MajorRegion->most_specific_matching_region_id("RU", "Somewhere", "Blahblahblah");
    is($regid, 63, "found that blahblahblah is in Russia");

    $regid = LJ::Directory::MajorRegion->region_id("US", "CA", "");
    is($regid, 10, "found California");

    is_deeply([sort LJ::Directory::MajorRegion->region_ids("RU")], [63,64,65], "found all russia regions");

    my $us_ids = [ LJ::Directory::MajorRegion->region_ids("US") ];
    is(scalar(@$us_ids), 62, "found all US regions");

}

# doing actual searches
memcache_stress(sub {
{
    my ($search, $res);

    $search = LJ::Directory::Search->new;
    ok($search, "made a search");

    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5"));
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "2,3,4,5,6,2,2,2,2,2,2,2"));

    $res = $search->search_no_dispatch;
    ok($res, "got a result");

    is($res->pages, 1, "just one page");
    is_deeply([$res->userids], [5,4,3,2], "got the right results back");

    # test paging
    $search = LJ::Directory::Search->new(page_size => 2, page => 2);
    is($search->page, 2, "requested page 2");
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9,10"));
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9,10,11,12,14,15,888888888"));
    $res = $search->search_no_dispatch;
    is($res->pages, 5, "five pages");
    is_deeply([$res->userids], [8,7], "got the right results back");

    # test paging, not even page size
    $search = LJ::Directory::Search->new(page_size => 2, page => 3);
    is($search->page, 3, "requested page 3");
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9"));
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "1,2,3,4,5,6,7,8,9,10,11,12,14,15,888888888"));
    $res = $search->search_no_dispatch;
    is($res->pages, 5, "five pages");
    is_deeply([$res->userids], [5,4], "got the right results back");

    # test update times
    $search = LJ::Directory::Search->new;
    $search->add_constraint(LJ::Directory::Constraint::UpdateTime->new(since => ($inittime - 4)));
    $res = $search->search_no_dispatch;
    is_deeply([$res->userids], [$usercount, $usercount - 1, $usercount - 2, $usercount - 3, $usercount - 4], "got recent posters");

    # test update times, after an initial et
    $search = LJ::Directory::Search->new;
    $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => "90,95,98,23,25,23"));
    $search->add_constraint(LJ::Directory::Constraint::UpdateTime->new(since => ($inittime - $usercount + 50)));
    $res = $search->search_no_dispatch;
    is_deeply([$res->userids], [98,95,90], "got correct answer (explicit set + first 50)");

    # test ages
    $search = LJ::Directory::Search->new;
    $search->add_constraint(LJ::Directory::Constraint::Age->new(from => 20, to => 35));
    $res = $search->search_no_dispatch;
    is_deeply([$res->userids], [reverse(20..35)], "got correct answer for age range (35..20)");

    # test ages after filter
    $search = LJ::Directory::Search->new;
    $search->add_constraint(LJ::Directory::Constraint::UpdateTime->new(since => ($inittime  - $usercount + 5)));
    $search->add_constraint(LJ::Directory::Constraint::Age->new(from => 97, to => 99));
    $res = $search->search_no_dispatch;
    is_deeply([$res->userids], [99, 98, 97], "ut + age correct");

    # test sub major regions
    $search = LJ::Directory::Search->new;
    $search->add_constraint(LJ::Directory::Constraint::Location->new(country => "US", state => "CA"));
    $res = $search->search_no_dispatch;
    ok(scalar($res->userids) > 0, "found a user or so in california");
}
});

# search with a huge number of ids (force it to use blobstore for set handles)
SKIP: {
    my ($search, $res);

    memcache_stress(sub {
        # test paging
        $search = LJ::Directory::Search->new(page_size => 100, page => 1);
        $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => join(",", 1..5000)));
        $search->add_constraint(LJ::Directory::Constraint::Test->new(uids => join(",", 51..6000)));
        $res = $search->search_no_dispatch;
        is($res->pages, 1, "50 pages");
        is_deeply([$res->userids], [reverse(51..100)], "got the right results back");
    });
}
