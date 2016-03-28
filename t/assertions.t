# t/assertions.t
#
# Test assertions TODO what's that?
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

use Test::More tests => 13;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

ok(LJ::assert_is("foo", "foo"));
ok(! eval { LJ::assert_is("foo", "bar") });

my $u = LJ::load_user("system");
ok($u->selfassert);
{
    local $u->{userid} = 9999;
    ok(! eval { $u->selfassert });
}
ok($u->selfassert);
{
    local $u->{user} = "systemNOT";
    ok(! eval { $u->selfassert });
}
ok($u->selfassert);
{
    local $u->{user} = "systemNOT";
    eval {
        my $u2 = LJ::DB::require_master( sub { LJ::load_userid($u->{userid}) } );
    };
    like($@, qr/AssertIs/);
}

{
    local $u->{user} = "systemNOT";
    eval {
        my $u2 = LJ::load_userid($u->{userid});
    };
    like($@, qr/AssertIs/);
}

{
    local $u->{userid} = 5555;
    eval {
        my $u2 = LJ::load_user("system");
    };
    like($@, qr/AssertIs/);
}

my $empty;
LJ::load_userids_multiple([ $u->{userid} => \$empty ]);
ok($empty == $u, "load multiple worked");

my $bogus = bless { userid => $u->{userid} + 1 }, 'LJ::User';
ok(! eval { LJ::load_userids_multiple([ $u->{userid} => \$bogus ]) });
like($@, qr/AssertIs/, "failed on blowing away existing user record");
