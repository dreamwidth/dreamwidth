#!/usr/bin/perl
#
# DW::Console::Command::Note
#
# Console commands for setting and clearing suspend notes. If a
# suspend note is set for an account, trying to suspend that
# account will cause an error and make you confirm you really
# want to do that.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Console::Command::Note;
use strict;

use base qw/ LJ::Console::Command /;

sub cmd { 'note' }

sub desc {
'Sets and clears notes that will display when you try to suspend an account. Intended for the antispam team to make notes on accounts frequently reported for spam that are actually legit. Requires priv: suspend.';
}

sub args_desc {
    [
        'command'  => 'Subcommand: add, remove.',
        'username' => 'Username to act on.',
        'note'     => 'Text of note to add. To remove, leave blank.',
    ]
}
sub usage { '<username> [<subcommand> <note>]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv('suspend');
}

sub execute {
    my ( $self, $user, $cmd, $note ) = @_;

    my $remote = LJ::get_remote();
    return $self->error('You must be logged in!')
        unless $remote;
    return $self->error('I\'m afraid I can\'t let you do that.')
        unless $remote->has_priv('suspend');

    my $u = LJ::load_user($user);
    return $self->error('Invalid user.')
        unless $u;

    my $currnote = $u->get_suspend_note;

    unless ( defined $cmd ) {

        # No subcommand to add or remove = print current note
        if ($currnote) {
            return $self->print( $u->user . "'s current note: " . $currnote );
        }
        else {
            return $self->print( $u->user . " has no note." );
        }
    }

    return $self->error('Invalid subcommand. Must be one of: add, remove.')
        if $cmd && $cmd !~ /^(?:add|remove)$/;

    if ( $cmd eq 'add' ) {
        return $self->error('Must specify a note to add.') unless $note;
        $u->set_prop( "suspendmsg", $note );
        $self->print( $u->user . "'s note added: " . $note );
        LJ::statushistory_add( $u, $remote, "note_add", $note );

    }
    elsif ( $cmd eq 'remove' ) {
        $u->clear_prop("suspendmsg");
        $self->print( $u->user . "'s note cleared." );
        LJ::statushistory_add( $u, $remote, "note_remove", $note );
    }

    return 1;
}

1;
