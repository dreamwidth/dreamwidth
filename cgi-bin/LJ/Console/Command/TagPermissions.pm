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

package LJ::Console::Command::TagPermissions;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "tag_permissions" }

sub desc { "Set tagging permission levels for an account. Requires priv: none." }

sub args_desc { [
                 'community' => "Optional; community to change permission levels for.",
                 'add level' => "Accounts at this level can add existing tags to entries. Value is one of 'public', 'access' (for personal journals), 'members' (for communities), 'author_admin' (for communities only), 'private', 'none', or a custom group name.",
                 'control level' => "Accounts at this level can do everything: add, remove, and create new tags. Value is one of 'public', 'access' (for personal journals), 'members' (for communities), 'private', 'none', or a custom group name.",
                 ] }

sub usage { '[ "for" <community> ] <add level> <control level>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return $self->error("Sorry, the tag system is currently disabled.")
        unless LJ::is_enabled('tags');

    return $self->error("This command takes either two or four arguments. Consult the reference.")
        unless scalar(@args) == 2 || scalar(@args) == 4;

    my $remote = LJ::get_remote();
    my $foru = $remote;            # may be overridden later
    my ($add, $control);

    if (scalar(@args) == 4) {  # community case
        return $self->error("Invalid arguments. First argument must be 'for'")
            if $args[0] ne "for";

        $foru = LJ::load_user($args[1]);
        return $self->error("Invalid account specified in 'for' parameter.")
            unless $foru;

        return $self->error("You cannot change tag permission settings for $args[1]")
            unless $remote && $remote->can_manage( $foru );

        $add = $args[2] eq 'members' ? 'protected' : $args[2];
        $control = $args[3] eq 'members' ? 'protected' : $args[3];
    } else {  # individual case
        $add = $args[0] eq 'access' ? 'protected' : $args[0];
        $control = $args[1] eq 'access' ? 'protected' : $args[1];
    }

    my $validate_level = sub {
        my $level = shift;
        return 'protected' if $level eq 'friends';
        return $level if $level =~ /^(?:private|public|none|protected|author_admin)$/;
        # can't use access for a community or members for an individual
        return undef if $level =~ /^(?:members|access)$/;

        my $grp = $foru->trust_groups( name => $level );
        return "group:$grp->{groupnum}" if $grp;

        return undef;
    };

    $add = $validate_level->($add);
    $control = $validate_level->($control);
    return $self->error("Levels must be one of: 'private', 'public', 'none', 'access' (for personal journals), 'members' (for communities), 'author_admin' (for communities only), or the name of a custom group.")
        unless $add && $control;
    return $self->error("Only <add level> can be 'author_admin'")
        if $control eq 'author_admin';
    return $self->error("'author_admin' level can be applied to communities only")
        if $add eq 'author_admin' && ! $foru->is_community;

    $foru->set_prop('opt_tagpermissions', "$add,$control");

    return $self->print("Tag permissions updated for " . $foru->user);
}

1;
