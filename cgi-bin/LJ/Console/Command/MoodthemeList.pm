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

package LJ::Console::Command::MoodthemeList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_list" }

sub desc { "List mood themes, or data about a mood theme. Requires priv: none." }

sub args_desc {
    [ 'themeid' =>
'Optional; mood theme ID to view data for. If not given, lists all available mood themes.'
    ]
}

sub usage { '[ <themeid> ]' }

sub requires_remote { 0 }

sub can_execute { 1 }

sub execute {
    my ( $self, $themeid, @args ) = @_;

    return $self->error("This command takes at most one argument. Consult the reference.")
        unless scalar(@args) == 0;

    if ($themeid) {
        my $theme = DW::Mood->new($themeid);
        return $self->error("This theme doesn't seem to exist.")
            unless $theme;
        foreach ( sort { $a->{name} cmp $b->{name} } values %{ DW::Mood->get_moods } ) {

            # make sure the mood is defined in this theme
            my $data = $theme->prop( $_->{id} );
            next unless defined $data;
            $self->info(
                sprintf(
                    "%-20s %2dx%2d %s",
                    "$_->{name} ($_->{id})",
                    $data->{w}, $data->{h}, $data->{pic}
                )
            );
        }
        return 1;
    }

    $self->info( sprintf( "%3s %4s %-15s %-25s %s", "pub", "id# ", "owner", "theme name", "des" ) );
    $self->info( "-" x 80 );

    $self->info("Public themes:");
    my @public_themes = DW::Mood->public_themes;
    my $owner         = LJ::load_userids( map { $_->{ownerid} } @public_themes );
    foreach (@public_themes) {
        my $u    = $owner->{ $_->{ownerid} };
        my $user = $u ? $u->user : '';
        $self->info(
            sprintf(
                "%3s %4s %-15s %-25s %s",
                $_->{is_public}, $_->{moodthemeid}, $user, $_->{name}, $_->{des}
            )
        );
    }

    my $remote = LJ::get_remote();
    if ($remote) {
        $self->info("Your themes:");
        foreach ( DW::Mood->get_themes( { ownerid => $remote->id } ) ) {
            $self->info(
                sprintf(
                    "%3s %4s %-15s %-25s %s",
                    $_->{is_public}, $_->{moodthemeid}, $remote->user, $_->{name}, $_->{des}
                )
            );
        }
    }

    return 1;
}

1;
