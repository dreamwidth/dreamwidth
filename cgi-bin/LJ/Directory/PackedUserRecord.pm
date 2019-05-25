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

package LJ::Directory::PackedUserRecord;
use strict;
use Carp qw(croak);

sub new {
    my ( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    foreach my $f (qw(updatetime age journaltype regionid)) {
        $self->{$f} = delete $args{$f};
    }
    croak("Unknown args") if %args;
    return $self;
}

sub packed {
    my $self = shift;
    return pack(
        "NCCCx",
        $self->{updatetime} || 0,
        $self->{age}        || 0,

        # the byte after age is a bunch of packed fields:
        #   u_int8_t  journaltype:2; // 0: person, 1: openid, 2: comm, 3: syn
        (
            {
                P => 0,
                I => 1,
                C => 2,
                Y => 3,
            }->{ $self->{journaltype} }
                || 0
        ) << 0 + 0,
        $self->{regionid} || 0
    );

}

1;
