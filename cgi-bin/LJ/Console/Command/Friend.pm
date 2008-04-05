package LJ::Console::Command::Friend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "friend" }

sub desc { "List your friends or add/remove a user from your friends list." }

sub args_desc { [
                 'command' => "Either 'list' to list friend, 'add' to add a friend, or 'remove' to remove a friend.",
                 'user' => "The username of the person to add or remove when using the add or remove command.",
                 'group' => "Optional; when using 'add', adds the user to this friend group. It must already exist.",
                 'fgcolor' => "Optional; when using 'add', specifies the foreground color. Must be of form 'fgcolor=#hex'",
                 'bgcolor' => "Optional; when using 'add', specifies the background color. Must be of form 'bgcolor=#hex'",
                 ] }

sub usage { '<command> <user> [ <group> ] [ <fgcolor> ] [ <bgcolor> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, $command, $user, @args) = @_;

    return $self->error("This command takes at least one argument, and no more than five. Consult the reference.")
        unless $command && scalar(@args) <= 3;

    return $self->error("Invalid command. Must be one of: 'list', 'add', or 'remove'.")
        unless $command =~ /^(?:list|add|remove)$/;

    my $remote = LJ::get_remote();

    if ($command eq "list") {
        # TAG:FR:console:friend:getfriends
        my $dbh = LJ::get_db_reader();
        my $sth = $dbh->prepare("SELECT u.user, u.name, u.statusvis, u.journaltype FROM user u, friends f ".
                                "WHERE u.userid=f.friendid AND f.userid=? ORDER BY u.user");
        $sth->execute($remote->id);

        $self->info(sprintf("%-15s S T  Name", "User"));
        $self->info("-" x 58);

        while (my ($username, $name, $statusvis, $type) = $sth->fetchrow_array) {
            $statusvis = "" if $statusvis eq "V";
            $type = "" if $type eq "P";

            $self->info(sprintf("%-15s %1s %1s  %s", $username, $statusvis, $type, $name));
        }

        return 1;
    }

    # at this point we're doing an add or a remove
    my $fu = LJ::load_user($user);
    return $self->error("Invalid username: $user")
        unless $fu;

    if ($command eq "remove") {
        return $self->error("$user is not on your friends list")
            unless $remote->has_friend($fu);

        if ($remote->remove_friend($fu)) {
            return $self->print("$user removed from friends list.");
        } else {
            return $self->error("Error removing $user from friends list.")
        }
    }

    if ($command eq "add") {
        my $errmsg;
        return $self->error($errmsg)
            unless $remote->can_add_friends(\$errmsg);

        return $self->error("You cannot add inactive journals to your Friends list.")
            unless $fu->is_visible;

        my ($group, $fg, $bg);
        foreach (@args) {
            last unless $_;
            $fg = $1 and next if m!fgcolor=(.*)!;
            $bg = $1 and next if m!bgcolor=(.*)!;
            $group = $_;
        }

        my $gmask = 0;
        if ($group ne "") {
            my $grp = LJ::get_friend_group($remote->id, { name => $group });
            my $num = $grp ? $grp->{groupnum}+0 : 0;
            if ($num) {
                $gmask = 1 | 1 << $num; # friends-only bit, group bit
            } else {
                $self->error("You don't have a group called '$group'.");
            }
        }

        my $opts = {};
        $opts->{'groupmask'} = $gmask if $gmask;
        $opts->{'fgcolor'} = $fg if $fg;
        $opts->{'bgcolor'} = $bg if $bg;

        if ($remote->add_friend($fu, $opts)) {
            return $self->print("$user added as a friend.");
        } else {
            return $self->error("Error adding $user to friends list.");
        }
    }
}

1;
