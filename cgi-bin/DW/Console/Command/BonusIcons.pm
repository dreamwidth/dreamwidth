#!/usr/bin/perl
#
# DW::Console::Command::BonusIcons
#
# Console commands for managing bonus icons.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Alex Brett <kaberett@dreamwidth.org>
#
# Copyright (c) 2012-2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Console::Command::BonusIcons;
use strict;

use base qw/ LJ::Console::Command /;
use Carp qw/ croak /;
use List::Util qw/ max /;

sub cmd { 'bonus_icons' }
sub desc { 'Manage bonus icons for an account. Requires priv: payments:bonus_icons.' }
sub args_desc {
    [
        'command' => 'Subcommand: add, remove, xfer.',
        'username' => 'Username to act on.',
        'commandargs' => "'add' and 'remove' take one argument: count (the number
                          of icons to add or remove). 'xfer' takes one argument:
                          the target username (for icons to be transferred to)."
    ]
}
sub usage { '<username> [<subcommand> <commandargs>]' }
sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( 'payments' => 'bonus_icons' );
}

sub execute {
    my ( $self, $user, $cmd, $cmdarg ) = @_;

    my $remote = LJ::get_remote();
    return $self->error( 'You must be logged in!' )
        unless $remote;
    return $self->error( 'I\'m afraid I can\'t let you do that.' )
        unless $remote->has_priv( 'payments' => 'bonus_icons' );

    my $to_u = LJ::load_user( $user );
    return $self->error( 'Invalid user.' )
        unless $to_u;

    unless ( defined $cmd ) {
        # No subcommand to add or remove. Just print how many icons they have.
        return $self->print( sprintf( '%s has %d bonus icons.',
                $to_u->user, $to_u->prop( 'bonus_icons' ) ) );
    }

    return $self->error( 'Invalid subcommand.' )
        if $cmd && $cmd !~ /^(?:add|remove|xfer)$/;

    if ( $cmd eq 'add' || $cmd eq 'remove' ) {

        my $count = $cmdarg;

        return $self->error( 'Count must be a positive integer.' )
            unless $count =~ /^\d+$/;
        $count += 0;

        if ( $cmd eq 'add' ) {
            my $new = max( $to_u->prop( 'bonus_icons' ) + $count, 0 );
            $to_u->set_prop( bonus_icons => $new );
            LJ::statushistory_add( $to_u, $remote, 'bonus_icons',
                    sprintf( 'Added %d icons, new total: %d.', $count, $new ) );
            $self->print( sprintf( 'User now has %d icons.', $new ) );

        } elsif ( $cmd eq 'remove' ) {
            my $new = max( $to_u->prop( 'bonus_icons' ) - $count, 0 );
            $to_u->set_prop( bonus_icons => $new );
            LJ::statushistory_add( $to_u, $remote, 'bonus_icons',
                    sprintf( 'Removed %d icons, new total: %d.', $count, $new ) );
            $self->print( sprintf( 'User now has %d icons.', $new ) );

        }

    } elsif ( $cmd eq 'xfer' ) {
        my $destination_u = LJ::load_user( $cmdarg );

        return $self->error( 'Invalid target user.' )
            unless $destination_u;
        return $self->error( 'E-mail addresses do not match.' )
            unless $to_u->has_same_email_as( $destination_u );
        return $self->error( 'One or more email address(es) not confirmed.' )
            unless $to_u->is_validated && $destination_u->is_validated;

        my $xfer_count = $to_u->prop( 'bonus_icons' );
        $to_u->set_prop( bonus_icons => 0 );
        LJ::statushistory_add( $to_u, $remote, 'bonus_icons',
                sprintf( 'Transferred %d icons to %s.', $xfer_count,
                    $destination_u->user ) );
        my $new_total = $destination_u->prop( 'bonus_icons' ) + $xfer_count;
        $destination_u->set_prop( bonus_icons => $new_total );
        LJ::statushistory_add( $destination_u, $remote, 'bonus_icons',
                sprintf( 'Received %d icons from %s, new total: %d.',
                    $xfer_count, $to_u->user, $new_total ) );
        $self->print( sprintf( '%s now has %d icons.', $destination_u->user,
            $new_total ) );

    }

    return 1;
}

1;
