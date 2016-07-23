#!/usr/bin/perl
#
# DW::Console::Command::ScreenList
#
# Console command for listing users currently under selective screening for a given account.
# Based on LJ::Console::Command::BanList
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

package DW::Console::Command::ScreenList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "screen_list" }

sub desc { "Lists users who are being automatically screened by an account. Requires priv: none." }

sub args_desc { [
                 'user' => "Optional; lists automatic screens in a community you maintain, or any user if you have the 'finduser' priv."
                 ] }

sub usage { '[ "from" <user> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;
    my $remote = LJ::get_remote();
    my $journal = $remote;         # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless scalar(@args) == 0 || scalar(@args) == 2;

    if (scalar(@args) == 2) {
        my ($from, $user) = @args;

        return $self->error("First argument must be 'from'")
            if $from ne "from";

        $journal = LJ::load_user($user);
        return $self->error("Unknown account: $user")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless $remote && ( $remote->can_manage( $journal )
                                || $remote->has_priv( "finduser" ) );
    }

    my $screenids = LJ::load_rel_user($journal, 'S') || [];
    my $us = LJ::load_userids(@$screenids);
    my @userlist = map { $us->{$_}{user} } keys %$us;

    return $self->info($journal->user . " is not automatically screening any other users.")
        unless @userlist;

    $self->info($_) foreach @userlist;

    return 1;
}

1;
