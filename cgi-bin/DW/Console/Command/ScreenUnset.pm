#!/usr/bin/perl
#
# DW::Console::Command::ScreenUnset
#
# Console command for removing a user from selective screening for a given account.
# Based on LJ::Console::Command::BanUnset
#
# Authors:
#      Paul Niewoonder <woggy@dreamwidth.org>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Console::Command::ScreenUnset;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "screen_unset" }

sub desc { "Remove automatic screening on a user. Requires priv: none." }

sub args_desc { [
                 'user' => "The user you want to remove automatic screening from.",
                 'community' => "Optional; to remove automatic screening from a user in a community you maintain.",
               ] }

sub usage { '<user> [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, $user, @args) = @_;
    my $remote = LJ::get_remote();
    my $journal = $remote;         # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless $user && (scalar(@args) == 0 || scalar(@args) == 2);

    if (scalar(@args) == 2) {
        my ($from, $comm) = @args;
        return $self->error("First argument must be 'from'")
            if $from ne "from";

        $journal = LJ::load_user($comm);
        return $self->error("Unknown account: $comm")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless $remote && $remote->can_manage( $journal );
    }

    my $screenuser = LJ::load_user($user);
    return $self->error("Unknown account: $user")
        unless $screenuser;

    LJ::clear_rel($journal, $screenuser, 'S');
    $journal->log_event('screen_unset', { actiontarget => $screenuser->id, remote => $remote });

    return $self->print("Comments from user " . $screenuser->user . " in " . $journal->user . " will no longer be automatically screened.");
}

1;
