# t/betafeatures.t
#
# Test LJ::BetaFeatures
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

use Test::More tests => 12;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use LJ::BetaFeatures;

my $u = LJ::Test::temp_user();

{
    ok(ref LJ::BetaFeatures->get_handler('foo') eq 'LJ::BetaFeatures::default', "instantiated default handler");
}

{
    ok(! $u->in_class('betafeatures'), "cap not set");
    ok(! defined $u->prop('betafeatures_list'), "prop not set");

    LJ::BetaFeatures->add_to_beta($u => 'foo');
    ok($u->in_class('betafeatures'), "cap set after add");
    ok($u->prop('betafeatures_list') eq 'foo', 'prop set after add');

    LJ::BetaFeatures->add_to_beta($u => 'foo');
    ok($u->prop('betafeatures_list') eq 'foo', 'no dup');

    ok(LJ::BetaFeatures->user_in_beta($u => 'foo'), "user_in_beta true");

    $u->prop('betafeatures_list' => 'foo,foo,foo');
    ok(LJ::BetaFeatures->user_in_beta($u => 'foo'), "user_in_beta true with dups");

    ok($u->prop('betafeatures_list') eq 'foo', "no more dups");

    $LJ::BETA_FEATURES{foo}->{end_time} = 0;
    ok(! LJ::BetaFeatures->user_in_beta($u => 'foo'), "expired");
    ok(! $u->in_class('betafeatures'), "cap unset");
    ok(! defined $u->prop('betafeatures_list'), "prop no longer defined");

    # FIXME: more!
    # -- BetaFeatures::t_handler dies unless $LJ::T_FOO ?
}
