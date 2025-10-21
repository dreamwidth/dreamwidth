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

package LJ::Directory::Constraint::Age;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

use LJ::Directory::SetHandle::Age;

sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(from to);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ( $pkg, $args ) = @_;
    return undef unless $args->{age_min} || $args->{age_max};

    # only want to validate age in the case where constraint is user-generated
    # (that is, we don't want/need to do this in the 'new' ctor above)
    $args->{age_min} = 14 if $args->{age_min} && $args->{age_min} < 14;
    return $pkg->new(
        from => int( $args->{age_min} || 14 ),
        to   => int( $args->{age_max} || 125 )
    );
}

sub cached_sethandle {
    my ($self) = @_;
    return $self->sethandle;
}

sub sethandle {
    my ($self) = @_;
    return LJ::Directory::SetHandle::Age->new( $self->{from}, $self->{to} );
}

sub cache_for { 86400 }

1;
