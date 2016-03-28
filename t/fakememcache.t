# t/fakememcache.t
#
# Test LJ::MemCache with fake memcache.
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

use Test::More tests => 32;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test;

my $ret;
foreach my $key (sub { $_[0] }, sub { [5, $_[0]] }) {
    with_fake_memcache {
        is(LJ::MemCache::get($key->("name")), undef, "cache starts empty");
        ok(LJ::MemCache::add($key->("name"), "bob"), "added bob");
        is(LJ::MemCache::get($key->("name")), "bob", "cache starts empty");
        ok(! LJ::MemCache::add($key->("name"), "bob"), "didn't add bob again");
        ok(! LJ::MemCache::replace($key->("name2"), "mary"), "couldn't replace mary");
        ok(LJ::MemCache::replace($key->("name"), "mary"), "replaced bob with mary");
        is(LJ::MemCache::get($key->("name")), "mary", "cache now mary");
        ok(LJ::MemCache::delete($key->("name")), "deleted mary");
        is(LJ::MemCache::get($key->("name")), undef, "name now empty again");

        ok(LJ::MemCache::set($key->("name"), "bob"));
        ok(LJ::MemCache::set($key->("age"), "26"));

        is_deeply(LJ::MemCache::get_multi($key->("name"), "age", "bogus"),
                  {
                      "name" => "bob",
                      "age" => "26",
                  }, "get_multi worked");
    }
}

my @tests = (
             # first round, with no memcache settings:
             sub {
                 is(LJ::MemCache::get("name"), undef, "name undef");
                 ok(! LJ::MemCache::set("name", "bob"), "failed to set");
                 is(LJ::MemCache::get("name"), undef, "name still undef");
             },
             # now with a memcache
             sub {
                 is(LJ::MemCache::get("name"), undef, "name undef");
                 ok(LJ::MemCache::set("name", "bob"), "but we set");
                 is(LJ::MemCache::get("name"), "bob", "and got");
             },
             # again, using same memcache:
             sub {
                 is(LJ::MemCache::get("name"), "bob", "and still bob");
             },
             );

memcache_stress {
    my $test = shift @tests
        or die;
    $test->();
};

is(scalar @tests, 0, "no tests left");

