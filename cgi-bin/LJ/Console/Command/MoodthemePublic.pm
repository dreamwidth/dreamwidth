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

package LJ::Console::Command::MoodthemePublic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_public" }

sub desc { "Mark a mood theme as public or not. Requires priv: moodthememanager." }

sub args_desc {
    [
        'themeid' => "Mood theme ID number.",
        'setting' => "Either 'Y' or 'N' to make it public or not public, respectively.",
    ]
}

sub usage { '<themeid> <setting>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("moodthememanager");
}

sub execute {
    my ( $self, $themeid, $public, @args ) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $themeid && $public && scalar(@args) == 0;

    return $self->error("Setting must be either 'Y' or 'N'")
        unless $public =~ /^[YN]$/;

    my $theme = DW::Mood->new($themeid);
    return $self->error("This theme doesn't seem to exist.")
        unless $theme;

    my $msg = ( $public eq "Y" ) ? "public" : "not public";
    return $self->error("This theme is already marked as $msg.")
        if $theme->is_public eq $public;

    return $self->error("Failed to update theme.")
        unless $theme->update( 'is_public' => $public );

    return $self->print("Theme #$themeid marked as $msg.");
}

1;
