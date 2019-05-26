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

package LJ::Console::Command::SysbanAdd;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

use LJ::Sysban;

sub cmd { "sysban_add" }

sub desc { "Block an action based on certain criteria. Requires priv: sysban." }

sub args_desc {
    [
        'what'  => "The criterion you're blocking",
        'value' => "The value you're blocking",
        'days'  => "Length of the ban, in days (or 0 for forever)",
        'note'  => "Reason why you're setting this ban",
    ]
}

sub usage { '<what> <value> [ <days> ] [ <note> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("sysban");
}

sub execute {
    my ( $self, $what, $value, $days, $note, @args ) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $what && $value && scalar(@args) == 0;

    my $remote = LJ::get_remote();
    return $self->error("You cannot create these ban types")
        unless $remote && $remote->has_priv( "sysban", $what );

    my $err = LJ::Sysban::validate( $what, $value );
    return $self->error($err) if $err;

    $days ||= 0;
    return $self->error("You must specify a numeric value for the length of the ban")
        unless $days =~ /^\d+$/;

    my $banid = LJ::Sysban::create(
        'what'    => $what,
        'value'   => $value,
        'bandays' => $days,
        'note'    => $note,
    );

    return $self->error("There was a problem creating the ban.")
        unless $banid;

    return $self->print("Successfully created ban #$banid");
}

1;
