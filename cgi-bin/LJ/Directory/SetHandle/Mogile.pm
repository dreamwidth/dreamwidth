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

package LJ::Directory::SetHandle::Mogile;
use strict;
use base 'LJ::Directory::SetHandle';

use LWP::UserAgent;

use DW::BlobStore;

sub new {
    my ( $class, $conskey ) = @_;

    my $self = { conskey => $conskey, };

    return bless $self, $class;
}

sub new_from_string {
    my ( $class, $str ) = @_;
    $str =~ s/^Mogile:// or die;
    return $class->new($str);
}

sub as_string {
    my $self = shift;
    return "Mogile:" . $self->{conskey};
}

# Return scalarref of data, or die on failure to load
sub _load {
    my $self = $_[0];

    return $self->{data}
        if exists $self->{data};
    $self->{data} = DW::BlobStore->retrieve( directorysearch => $self->mogkey )
        or die "Failed to load search results!";
    return $self->{data};
}

sub pack_size {
    my $self = $_[0];
    return length( ${ $self->_load } );
}

sub load_pack_data {
    my ( $self, $cb ) = @_;
    $cb->( ${ $self->_load } );
    return;
}

sub mogkey {
    my $self = shift;
    return "dsh:" . $self->{conskey};
}

1;
