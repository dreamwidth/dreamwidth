package LJ::Console::Command::TagPermissions;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "tag_permissions" }

sub desc { "Set tagging permission levels for an account." }

sub args_desc { [
                 'community' => "Optional; community to change permission levels for.",
                 'add level' => "Accounts at this level can add existing tags to entries. One of 'public', 'friends', 'private', or a custom friend group name.",
                 'control level' => "Accounts at this level can do everything: add, remove, and create new ones. Value is one of 'public', 'friends', 'private', or a custom friend group name.",
                 ] }

sub usage { '[ "for" <community> ] <add level> <control level>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return $self->error("Sorry, the tag system is currently disabled.")
        if $LJ::DISABLED{tags};

    return $self->error("This command takes either two or four arguments. Consult the reference.")
        unless scalar(@args) == 2 || scalar(@args) == 4;

    my $remote = LJ::get_remote();
    my $foru = $remote;            # may be overridden later
    my ($add, $control);

    if (scalar(@args) == 4) {
        return $self->error("Invalid arguments. First argument must be 'for'")
            if $args[0] ne "for";

        $foru = LJ::load_user($args[1]);
        return $self->error("Invalid account specified in 'for' parameter.")
            unless $foru;

        return $self->error("You cannot change tag permission settings for $args[1]")
            unless LJ::can_manage($remote, $foru);

        ($add, $control) = ($args[2], $args[3]);
    } else {
        ($add, $control) = ($args[0], $args[1]);
    }

    my $validate_level = sub {
        my $level = shift;
        return $level if $level =~ /^(?:private|public|none|friends)$/;

        my $grp = LJ::get_friend_group($foru, { name => $level });
        return "group:$grp->{groupnum}" if $grp;

        return undef;
    };

    $add = $validate_level->($add);
    $control = $validate_level->($control);
    return $self->error("Levels must be one of: 'private', 'public', 'friends', or the name of a friends group.")
        unless $add && $control;

    $foru->set_prop('opt_tagpermissions', "$add,$control");

    return $self->print("Tag permissions updated for " . $foru->user);
}

1;
