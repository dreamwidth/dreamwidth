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

package LJ::Directory::Constraint::Interest;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

# wants intid
sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(intid interest);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ( $pkg, $args ) = @_;
    return undef unless ( $args->{int_like} xor $args->{intid} );

    # handle possibility of multiple specified interests
    my @ints = LJ::interest_string_to_list( $args->{int_like} );

    if ( $args->{int_like} ) {
        return [ map { $pkg->new( interest => $_ ) } @ints ];
    }
    else {
        return $pkg->new( intid => $args->{intid} );
    }
}

sub cache_for { 5 * 60 }

sub intid {
    my $self = shift;
    $self->load_row unless $self->{_loaded_row};
    return $self->{intid} || 0;
}

sub load_row {
    my $self = shift;
    $self->{_loaded_row} = 1;

    if ( $self->{interest} && !$self->{intid} ) {
        $self->{intid} = LJ::get_sitekeyword_id( $self->{interest}, 0 );
    }
    return unless $self->{intid};

    ( $self->{interest}, $self->{intcount} ) = LJ::get_interest( $self->{intid} );
}

sub matching_uids {
    my $self = shift;
    return unless $self->intid;

    my $db = LJ::get_dbh("directory") || LJ::get_db_reader();

    # user interests
    my @ids = @{
        $db->selectcol_arrayref( "SELECT userid FROM userinterests WHERE intid=?",
            undef, $self->intid )
            || []
    };

    # community interests
    push @ids,
        @{
        $db->selectcol_arrayref( "SELECT userid FROM comminterests WHERE intid=?",
            undef, $self->intid )
            || []
        };

    # deal with the case where a journal
    # has interests in both tables ... ew
    my %seen;
    return grep { !$seen{$_}++ } @ids;
}

1;
