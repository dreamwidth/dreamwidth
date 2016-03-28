# t/errors.t
#
# Test LJ::Errors
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

use Test::More tests => 23;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

# old calling conventions unmodified:  return undef on no dbh
my $db = LJ::get_dbh("foo", "bar");
ok(! defined $db, "undef for foo/bar roles");

{
    # declare that for this block, all functions everywhere
    # should throw errors if possible.
    local $LJ::THROW_ERRORS = 1;

    # so now this should actually die:
    $db = eval {
        LJ::get_dbh("foo", "bar");
    };
    is(ref $@, "LJ::Error::Database::Unavailable", "got no db object");
    ok(! defined $db, "still no database");
}

# test errobj creating an object
my $ero = LJ::errobj("DieString", message => "My test message");
is(ref $ero, "LJ::Error::DieString", "made a die error");
like($ero->die_string, qr/test message/, "got test message");
eval {
    $ero->field("XXXbad");
};
like($@, qr/Invalid field/i, "bogus field threw");

# test errobj wrapping a normal die
my $val = eval {
    die "A normal error message";
};
$ero = LJ::errobj();
is(ref $ero, "LJ::Error::DieString", "got die string object");
like($ero->die_string, qr/A normal error message/, "got message back");

# test errobj wrapping another exception object
$val = eval {
    die { foo => "bar" };
};
$ero = LJ::errobj($@);
is(ref $ero, "LJ::Error::DieObject", "got die object back");
is(ref ($ero->die_object), "HASH", "got a hashback");
is($ero->die_object->{foo}, "bar", "and it's ours");

# test errobj returning an errobj
my $pre = $ero;
my $post = LJ::errobj($pre);
is($pre, $post, "errobj passed through unchanged");

# test alloc_global_counter
my $id = LJ::alloc_global_counter("ooooo");
ok(! defined $id, "undef id");
eval {
    local $LJ::THROW_ERRORS = 1;
    $id = LJ::alloc_global_counter("ooooo");
};
$ero = $@;
is(ref $ero, "LJ::Error::InvalidParameters", "got invalid parameters");
is($ero->field("params")->{dom}, "ooooo", "got bad param back out");

# testing optional fields
$ero = LJ::errobj("OptFields", foo => 34);
ok($ero);
$ero = LJ::errobj("OptFields", bar => 36);
ok($ero);
$ero = eval { LJ::errobj("OptFields", bad => 36); };
ok(!$ero, "opt fields bad");

# testing required fields
$ero = eval { LJ::errobj("ReqFields", foo => 34); };
ok(!$ero, "fail req fields");
$ero = LJ::errobj("ReqFields", bar => 36, foo => 23);
ok($ero, "req fields");

my $u = LJ::load_user("system");
$u->do("UPDATE non_exist_table SET foo=bar");
$ero = LJ::errobj($u);
is(ref $ero, "LJ::Error::Database::Failure", "got db failure");
is($ero->err, 1146, "got error 1146");
like($ero->errstr, qr/non_exist_table.+doesn\'t exist/, "table not there");


package LJ::Error::OptFields;
sub opt_fields { qw(foo bar); }

package LJ::Error::ReqFields;
sub fields { qw(foo bar); }
