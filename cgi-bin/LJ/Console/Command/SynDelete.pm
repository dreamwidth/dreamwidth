#!/usr/bin/perl
#
# LJ::Console::Command::SynDelete
#
# Console command to delete a syndicated (RSS/Atom feed) account. Marks
# the account as deleted so the syndication system stops refreshing it
# and it eventually gets purged like any other deleted account. Use
# syn_undelete to reverse this.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Console::Command::SynDelete;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_delete" }

sub desc {
    "Deletes a syndicated (RSS/Atom feed) account, marking it for purging and stopping the "
        . "syndication system from refreshing it. Use syn_undelete to reverse this. "
        . "Requires priv: syn_edit.";
}

sub args_desc {
    [ 'user' => "The username of the syndicated account to delete.", ]
}

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("syn_edit");
}

sub execute {
    my ( $self, $user, @args ) = @_;

    return $self->error("This command takes one argument. Consult the reference.")
        unless $user && scalar(@args) == 0;

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;
    return $self->error("Not a syndicated account")
        unless $u->is_syndicated;
    return $self->error("Cannot modify a purged account.")
        if $u->is_expunged;
    return $self->error("Account is already deleted.")
        if $u->is_deleted;

    $u->set_deleted;

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, 'synd_delete',
        "Feed account deleted; syndication checking stopped." );

    return $self->print(
        "Feed account $user marked as deleted; the syndication system will stop refreshing it.");
}

1;
