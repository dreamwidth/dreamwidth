#!/usr/bin/perl
#
# DW::User::Edges
#
# This module defines relationships between accounts.  It allows for finding
# edges, defining edges, removing edges, and other tasks related to the edges
# that can exist between accounts.  Methods are added to the LJ::User/DW::User
# classes as appropriate.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Console::Command::ManageCircle;
use strict;

use base qw/ LJ::Console::Command /;
use Carp qw/ croak /;

sub cmd { 'manage_circle' }
sub desc { 'Manage your circle of relationships. Requires priv: none.' }
sub args_desc {
    [
        'command' => 'Subcommand: add_read, del_read, add_access, del_access.',
        'username' => 'Username to act on.',
        'groups' => 'If using add_access, a comma separated list of trust group ids. Will add to the list of groups this user is already in.',
    ]
}
sub usage { '<subcommand> <username> [groups]' }
sub can_execute { 1 }

sub execute {
    my ( $self, $cmd, $user, $grouplist, @args ) = @_;

    return $self->error( 'Invalid command.' )
        unless $cmd && $cmd =~ /^(?:add_read|del_read|add_access|del_access|get_read|get_access)$/;

    my $to_u = LJ::load_user( $user );
    return $self->error( 'Invalid user.' )
        unless $to_u;

    my @groups = grep { $_ >= 1 && $_ <= 60 } map { $_+0 } split( /,/, $grouplist || '' );
    return $self->error( 'Invalid groups, try something like: 3,4,19,23' )
        if $grouplist && scalar( @groups ) <= 0;
    return $self->error( 'Can only specify groups for add_access command.' )
        if $cmd ne 'add_access' && @groups;

    my $remote = LJ::get_remote();
    return $self->error( 'You must be logged in, dude!' )
        unless $remote;

    my $edge_err;

    if ( $cmd eq 'add_read' ) {
        if ( $remote->can_watch( $to_u, errref => \$edge_err ) ) {
            $remote->add_edge( $to_u, watch => {
                nonotify => $remote->watches( $to_u ) ? 1 : 0,
            } );
        } else {
            return $self->error( "Error: $edge_err" );
        }

    } elsif ( $cmd eq 'del_read' ) {
        $remote->remove_edge( $to_u, watch => {
            nonotify => $remote->watches( $to_u ) ? 0 : 1,
        } );

    } elsif ( $cmd eq 'add_access' ) {
        my $mask = 0;
        $mask += ( 1 << $_ ) foreach @groups;
        
        my $existing_mask = $remote->trustmask( $to_u );
        $mask |= $existing_mask;

        if ( $remote->can_trust( $to_u, errref => \$edge_err ) ) {
            $remote->add_edge( $to_u, trust => {
                mask => $mask,
                nonotify => $remote->trusts( $to_u ) ? 1 : 0,
            } );
        } else {
            return $self->error( "Error: $edge_err" );
        }

    } elsif ( $cmd eq 'del_access' ) {
        $remote->remove_edge( $to_u, trust => {
            nonotify => $remote->trusts( $to_u ) ? 0 : 1,
        } );

    } elsif ( $cmd eq 'get_read' ) {

    }

    $self->print( 'Done.' );

# $self->print
# self->info
# self->error

    return 1;
}

1;
