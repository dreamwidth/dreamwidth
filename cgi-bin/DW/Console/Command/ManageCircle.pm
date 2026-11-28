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

sub cmd  { 'manage_circle' }
sub desc { 'Manage your circle of relationships. Requires priv: none.' }

sub args_desc {
    [
        'command'  => 'Subcommand: add_read, del_read, add_access, del_access.',
        'username' => 'Username to act on.',
        'groups' =>
'If using add_access, a comma separated list of trust group ids. Will add to the list of groups this user is already in.',
    ]
}
sub usage       { '<subcommand> <username> [groups]' }
sub can_execute { 1 }

sub execute {
    my ( $self, $cmd, $user, $grouplist, @args ) = @_;

    return $self->error('Invalid command.')
        unless $cmd && $cmd =~ /^(?:add_read|del_read|add_access|del_access|get_read|get_access)$/;

    my $to_u = LJ::load_user($user);
    return $self->error('Invalid user.')
        unless $to_u;

    my @groups = split /,/, $grouplist // '', -1;
    return $self->error('Invalid groups, try something like: 3,4,19,23')
        if grep { !/\A\s*\d{1,2}\s*\z/ || $_ < 1 || $_ > 60 } @groups;
    return $self->error('Can only specify groups for add_access command.')
        if $cmd ne 'add_access' && @groups;

    my $remote = LJ::get_remote();
    return $self->error('You must be logged in, dude!')
        unless $remote;

    my $edge_err;

    if ( $cmd eq 'add_read' ) {
        if ( $remote->can_watch( $to_u, errref => \$edge_err ) ) {
            $remote->add_edge(
                $to_u,
                watch => {
                    nonotify => $remote->watches($to_u) ? 1 : 0,
                }
            ) or return $self->error('Could not save Circle changes.');
        }
        else {
            return $self->error("Error: $edge_err");
        }

    }
    elsif ( $cmd eq 'del_read' ) {
        $remote->remove_edge(
            $to_u,
            watch => {
                nonotify => $remote->watches($to_u) ? 0 : 1,
            }
        ) or return $self->error('Could not save Circle changes.');

    }
    elsif ( $cmd eq 'add_access' ) {
        return $self->error("Error: $edge_err")
            unless $remote->can_trust( $to_u, errref => \$edge_err );

        my $saved = $remote->with_trust_groups_lock(
            sub {
                my $mask = $remote->trustmask_from_primary($to_u);
                return 0 unless defined $mask;

                if (@groups) {
                    my $owned = $remote->trust_groups( force_database => 1 ) or return 0;
                    if ( grep { !$owned->{ $_ + 0 } } @groups ) {
                        $edge_err = 'An access filter does not exist.';
                        return 0;
                    }
                }

                my $nonotify = $mask & 1 ? 1 : 0;
                $mask |= 1 << $_ foreach @groups;
                return $remote->add_edge( $to_u,
                    trust => { mask => $mask, nonotify => $nonotify } );
            }
        );
        return $self->error( $edge_err || 'Could not save Circle changes.' ) unless $saved;

    }
    elsif ( $cmd eq 'del_access' ) {
        $remote->remove_edge(
            $to_u,
            trust => {
                nonotify => $remote->trusts($to_u) ? 0 : 1,
            }
        ) or return $self->error('Could not save Circle changes.');

    }
    elsif ( $cmd eq 'get_read' ) {

    }

    $self->print('Done.');

    # $self->print
    # self->info
    # self->error

    return 1;
}

1;
