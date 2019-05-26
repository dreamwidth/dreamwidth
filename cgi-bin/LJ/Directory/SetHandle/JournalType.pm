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

package LJ::Directory::SetHandle::JournalType;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ( $class, $type ) = @_;
    return bless { type => $type, }, $class;
}

sub filter_search {
    my $sh  = shift;
    my $num = {
        P => 0,
        I => 1,
        C => 2,
        Y => 3,
    }->{ $sh->{type} };
    die "Bogus type" unless defined $num;
    LJ::UserSearch::isect_journal_type($num);
}

1;
