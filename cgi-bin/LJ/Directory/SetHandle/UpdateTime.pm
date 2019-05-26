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

package LJ::Directory::SetHandle::UpdateTime;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ( $class, $unixtime ) = @_;
    return bless { since => $unixtime, }, $class;
}

sub filter_search {
    my $sh = shift;
    LJ::UserSearch::isect_updatetime_gte( $sh->{since} );
}

1;
