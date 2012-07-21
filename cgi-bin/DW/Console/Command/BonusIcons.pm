#!/usr/bin/perl
#
# DW::Console::Command::BonusIcons
#
# Console commands for managing bonus icons.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
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
sub desc { 'Manage bonus icons for an account.' }
sub args_desc {
    [
        'command' => 'Subcommand: add, remove.',
        'username' => 'Username to act on.',
        'count' => 'How many icons to add or remove.',
    ]
}
sub usage { '<username> [<subcommand> <count>]' }
sub can_execute { 1 }

sub execute {
    my ( $self, $user, $cmd, $count ) = @_;

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
        if $cmd && $cmd !~ /^(?:add|remove)$/;

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

    return 1;
}

1;
