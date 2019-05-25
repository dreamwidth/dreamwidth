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

package LJ::ModuleCheck;
use strict;
use warnings;

my %have;

sub have {
    my ( $class, $modulename ) = @_;
    return $have{$modulename} if exists $have{$modulename};
    die "Bogus module name" unless $modulename =~ /^[\w:]+$/;
    return $have{$modulename} = eval "use $modulename (); 1;";
}

sub have_xmlatom {
    my ($class) = @_;
    return $have{"XML::Atom"} if exists $have{"XML::Atom"};
    return $have{"XML::Atom"} = eval q{
        use XML::Atom::Feed;
        use XML::Atom::Entry;
        use XML::Atom::Link;
        use XML::Atom::Category;
        XML::Atom->VERSION < 0.21 ? 0 : 1;
    };
}

1;
