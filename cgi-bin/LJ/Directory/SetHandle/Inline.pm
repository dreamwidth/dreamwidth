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

package LJ::Directory::SetHandle::Inline;
use strict;
use base 'LJ::Directory::SetHandle';

sub new {
    my ( $class, @set ) = @_;

    my $self = { set => \@set, };

    return bless $self, $class;
}

sub new_from_string {
    my ( $class, $str ) = @_;
    $str =~ s/^Inline:// or die;
    return $class->new( split( ',', $str ) );
}

sub as_string {
    my $self = shift;
    return "Inline:" . join( ',', @{ $self->{set} } );
}

sub set_size {
    my $self = shift;
    return scalar( @{ $self->{set} } );
}

sub load_matching_uids {
    my ( $self, $cb ) = @_;
    $cb->( @{ $self->{set} } );
}

1;
