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

package LJ::Console::Command::TagDisplay;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "tag_display" }

sub desc { "Set tag visibility to S2. Requires priv: none." }

sub args_desc {
    [
        'community' => "Community that this tag is in, if applicable.",
        'tag' =>
"The tag to change the display value of.  This must be quoted if it contains any spaces.",
        'value' => "Either 'on' to display tag, or 'off' to hide it.",
    ]
}

sub usage { '[ "for" <community> ] <tag> <value>' }

sub can_execute { 1 }

sub execute {
    my ( $self, @args ) = @_;

    return $self->error("Sorry, the tag system is currently disabled.")
        unless LJ::is_enabled('tags');

    return $self->error("This command takes either two or four arguments. Consult the reference.")
        unless scalar(@args) == 2 || scalar(@args) == 4;

    my $remote = LJ::get_remote();
    my $foru   = $remote;            # may be overridden later
    my ( $tag, $val );

    if ( scalar(@args) == 4 ) {
        return $self->error("Invalid arguments. First argument must be 'for'")
            if $args[0] ne "for";

        $foru = LJ::load_user( $args[1] );
        return $self->error("Invalid account specified in 'for' parameter.")
            unless $foru;

        return $self->error("You cannot change tag display settings for $args[1]")
            unless $remote && $remote->can_manage($foru);

        ( $tag, $val ) = ( $args[2], $args[3] );
    }
    else {
        ( $tag, $val ) = ( $args[0], $args[1] );
    }

    $val = { 1 => 1, 0 => 0, yes => 1, no => 0, true => 1, false => 0, on => 1, off => 0 }->{$val};

    return $self->error("Error changing tag value. Please make sure the specified tag exists.")
        unless LJ::Tags::set_usertag_display( $foru, name => $tag, $val );

    return $self->print("Tag display value updated.");
}

1;
