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

package LJ::Directory::SetHandle::MajorRegion;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ( $class, @ids ) = @_;
    return bless { ids => \@ids, }, $class;
}

sub filter_search {
    my $sh  = shift;
    my $reg = "\0" x 256;
    foreach my $id ( @{ $sh->{ids} } ) {
        next if $id > 255 || $id < 0;
        vec( $reg, $id, 8 ) = 1;
    }
    LJ::UserSearch::isect_region_map($reg);
}

1;
