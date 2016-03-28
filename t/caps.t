# t/caps.t
#
# Test LJ::get_cap
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
use LJ::Test qw( temp_user );

{
    my $c;

    $c = eval { LJ::get_cap(undef, 'something_not_defined') };
    is($c, undef, "Undef returns undef");

    $c = eval { LJ::get_cap(undef, 'can_post') };
    is($c, 1, "Undef returns default");


    my $u = temp_user();
    $LJ::T_HAS_ALL_CAPS = 1;
    $c = eval { $u->get_cap( 'anycapatall' ) };
    ok( $c, "Cap always on" );

    $c = eval { $u->get_cap( 'readonly' ) };
    ok( ! $c, "readonly cap is not automatically set enabled" );
}

1;

