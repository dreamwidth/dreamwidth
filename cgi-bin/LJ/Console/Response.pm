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

# Simple object to represent console responses

package LJ::Console::Response;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my %opts  = @_;

    my $self = {
        status => delete $opts{status},
        text   => delete $opts{text},
    };

    croak "invalid parameter: status"
        unless $self->{status} =~ /^(?:info|success|error)$/;

    croak "invalid parameters: ", join( ",", keys %opts )
        if %opts;

    return bless $self, $class;
}

sub status {
    my $self = shift;
    return $self->{status};
}

sub text {
    my $self = shift;
    return $self->{text};
}

sub is_success {
    my $self = shift;
    return $self->status eq 'success' ? 1 : 0;
}

sub is_error {
    my $self = shift;
    return $self->status eq 'error' ? 1 : 0;
}

sub is_info {
    my $self = shift;
    return $self->status eq 'info' ? 1 : 0;
}

sub as_string {
    my $self = shift;
    return join( ": ", $self->status, $self->text );
}

sub as_html {
    my $self = shift;

    my $color;
    if ( $self->is_error ) {
        $color = "#FF0000";
    }
    elsif ( $self->is_success ) {
        $color = "#008800";
    }
    else {
        $color = "#000000";
    }

    return "<span style='color:$color;'>" . LJ::eall( $self->text ) . "</span>";
}

1;
