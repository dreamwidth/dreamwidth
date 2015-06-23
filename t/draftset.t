# t/draftset.t
#
# Test TODO something about draft text for entries
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

my $u = LJ::load_user("system");
ok($u);

ok($u->set_draft_text("some new draft text"), "set it");
is($u->draft_text, "some new draft text", "it matches");

{
    my $meth;
    local $LJ::_T_METHOD_USED = sub {
        $meth = $_[0];
    };

    $meth = undef;
    ok($u->set_draft_text("some new draft text with more"), "set it");
    is($meth, "append", "did an append");

    ok($u->set_draft_text("new text"), "set it");
    is($meth, "set", "did a set");

    ok($u->set_draft_text("new text"), "set it");
    is($meth, "noop", "did a noop");

    # test race conditions with append
    ok($u->set_draft_text("test append"), "set it");
    is($meth, "set", "did a set");

    {
        local $LJ::_T_DRAFT_RACE = sub {
            my $prop = LJ::get_prop("user", "entry_draft") or die; # FIXME: use exceptions
            $u->do("UPDATE userpropblob SET value = 'gibberish' WHERE userid=? AND upropid=?",
                   undef, $u->{userid}, $prop->{id});
        };

        ok($u->set_draft_text("test append bar"), "appending during a race");
        is($meth, "set", "did a set");

        is($u->draft_text, "test append bar", "it matches");
        unlike($u->draft_text, qr/gibberish/, "no gibberish from race");
    }


}


