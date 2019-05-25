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

package LJ::Identity;

use strict;

use fields (
    'typeid',    # character defining identity type
    'value',     # Identity string
);

sub new {
    my LJ::Identity $self = shift;
    $self = fields::new($self) unless ref $self;
    my %opts = @_;

    $self->{typeid} = $opts{'typeid'};
    $self->{value}  = $opts{'value'};

    return $self;
}

sub pretty_type {
    my LJ::Identity $self = shift;
    return 'OpenID' if $self->{typeid} eq 'O';
    return 'Invalid identity type';
}

sub typeid {
    my LJ::Identity $self = shift;
    die("Cannot set new typeid value") if @_;

    return $self->{typeid};
}

sub value {
    my LJ::Identity $self = shift;
    die("Cannot set new identity value") if @_;

    return $self->{value};
}
1;
