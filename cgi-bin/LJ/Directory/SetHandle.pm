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

package LJ::Directory::SetHandle;
use strict;
use Carp qw (croak);

use LJ::Directory::SetHandle::Inline;
use LJ::Directory::SetHandle::Mogile;

sub new {
    my ($class) = @_;
    die "Unimplemented method 'new' on $class";
}

# override in subclasses.  but this generic version is the entry point
# for other people.
sub new_from_string {
    my ( $class, $shstr, $no_recurse ) = @_;
    die "Unimplemented method 'new_from_string' on class $class" if $no_recurse;
    foreach my $sb (qw(Inline Mogile)) {
        if ( $shstr =~ /^$sb:/ ) {
            my $class = "LJ::Directory::SetHandle::$sb";
            return $class->new_from_string( $shstr, "no_recurse" );
        }
    }
    die "Unknown set handle for handle: '$shstr'\n";
}

# override in subclasses
sub as_string {
    my $self = shift;
    die "Unimplemented method 'as_string' on $self";
}

# size of data, packed 4 bytes per int
sub pack_size {
    my $self = shift;
    return 4 * $self->set_size;
}

# abstract.  number of matching uids
sub set_size {
    my $self = shift;
    die "Unimplemented method 'set_size' on $self";
}

sub load_matching_uids {
    my ( $self, $cb ) = @_;
    die "Unimplemented method 'load_matching_uids' on $self";
}

# can optionally override this, otherwise calls load_matching_uids
# instead, and this will pack it for you.
sub load_pack_data {
    my ( $self, $cb ) = @_;
    $self->load_matching_uids(
        sub {
            $cb->( pack( "N*", @_ ) );
        }
    );
}

# default implementation.  can override for fanciness, if you want to interact
# with LJ::UserSearch:: directly.
sub filter_search {
    my $sh       = shift;
    my $packsize = $sh->pack_size;
    LJ::UserSearch::isect_begin($packsize);
    $sh->load_pack_data(
        sub {
            my $pd = shift;
            LJ::UserSearch::isect_push($pd);
        }
    );
    LJ::UserSearch::isect_end();
}

1;
