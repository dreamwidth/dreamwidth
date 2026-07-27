#!/usr/bin/perl
#
# LJ::Console::Command::SynUndelete
#
# Console command to undelete a syndicated (RSS/Atom feed) account that
# was previously deleted with syn_delete. Restores the account to visible
# and resets the check schedule so the syndication system resumes
# refreshing the feed.
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

package LJ::Console::Command::SynUndelete;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_undelete" }

sub desc {
    "Undeletes a syndicated (RSS/Atom feed) account that was deleted with syn_delete, "
        . "restoring it and resuming syndication checking. Requires priv: syn_edit.";
}

sub args_desc {
    [ 'user' => "The username of the syndicated account to undelete.", ]
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
    return $self->error("Account is not deleted.")
        unless $u->is_deleted;

    $u->set_visible;

    # nudge the scheduler to pick the feed up promptly and clear any
    # accumulated failures from before it was deleted.
    my $dbh = LJ::get_db_writer();
    $dbh->do( "UPDATE syndicated SET checknext=NOW(), failcount=0 WHERE userid=?", undef, $u->id );

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, 'synd_delete',
        "Feed account undeleted; syndication checking restored." );

    return $self->print(
        "Feed account $user restored; the syndication system will resume refreshing it.");
}

1;
