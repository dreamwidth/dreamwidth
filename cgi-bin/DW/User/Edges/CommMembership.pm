#!/usr/bin/perl
#
# DW::User::Edges::CommMembership
#
# Implements community membership edges.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2008 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::User::Edges::CommMembership;
use strict;

use Carp qw/ confess /;

# membership edges are for someone who is a member of a community
DW::User::Edges::define_edge(
        member =>
            {
                type => 'bool',
                db_edge => 'E',
                add_sub => \&_add_m_edge,
                del_sub => \&_del_m_edge,
            }
    );

# internal method used to add a membership edge to an account
sub _add_m_edge {
    my ( $from_u, $to_u, $edges ) = @_;

    # bail unless there is a membership edge; note that we have to remove
    # the edge, as per the Edges specification.  (if we don't, we will get
    # called over and over...)
    delete $edges->{member}
        or return;

    # error check adding an edge
    return 0 unless $from_u->can_join( $to_u );

    # simply add the reluser edge
    LJ::set_rel( $to_u, $from_u, 'E' );
}

# internal method to delete an edge
sub _del_m_edge {
    my ( $from_u, $to_u, $edges ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    # same logic as in _add_m_edge
    delete $edges->{member}
        or return;

    # now remove it; note we don't do any extraneous checking.  if the user
    # wants to remove an edge that doesn't exist?  more power to them.
    LJ::clear_rel( $to_u, $from_u, 'E' );

    # success!
    return 1;
}

###############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
###############################################################################

# push methods up into the DW::User namespace
package DW::User;
use strict;

use Carp qw/ confess /;


# returns 1 if the given user is a member of the community
# returns 0 otherwise
sub member_of {
    my ( $from_u, $to_u ) = @_;
    $from_u = LJ::want_user( $from_u ) or return 0;
    $to_u = LJ::want_user( $to_u ) or return 0;

    # person->comm
    return 0
        unless $from_u->is_person &&
               $to_u->is_community;

    # check it
    return 1 if LJ::check_rel( $to_u, $from_u, 'E' );
    return 0;
}
*LJ::User::member_of = \&member_of;


# returns array of userids we're member of
# you may specify one argument "force => 1" if you are unwilling to take
# potentially stale data.  otherwise, the results of this method may be up to
# 30 minutes out of date.
sub member_of_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or return ();

    return ()
        unless $u->is_person;

    return @{ LJ::load_rel_target( $u, 'E' ) || [] }
        if $args{force};

    return @{ LJ::load_rel_target_cache( $u, 'E' ) || [] };
}
*LJ::User::member_of_userids = \&member_of_userids;


# returns array of userids that are our members
# you may specify one argument "force => 1" if you are unwilling to take
# potentially stale data.  otherwise, the results of this method may be up to
# 30 minutes out of date.
sub member_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or return ();

    return ()
        unless $u->is_community;

    return @{ LJ::load_rel_user( $u, 'E' ) || [] }
        if $args{force};

    return @{ LJ::load_rel_user( $u, 'E' ) || [] };
}
*LJ::User::member_userids = \&member_userids;


# returns 1/0 depending on if the source is allowed to add a member edge
# to the target.  note: if you don't pass a target user, then we return
# a generic 1/0 meaning "this account is allowed to have a member edge".
sub can_join {
    my ( $u, $tu ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';
    $tu = LJ::want_user( $tu );

    # if the user is a maintainer, skip every other check
    return 1 if $tu && $u->can_manage( $tu );

    # a user must be a personal account
    return 0 unless $u->is_personal;

    # the user must be visible
    return 0 unless $u->is_visible;

    if ( $tu ) {
        # the target must be a community
        return 0 unless $tu->is_community;

        # the target must be visible
        return 0 unless $tu->is_visible;

        # the target must not have banned the user
        return 0 if $tu->has_banned( $u );

        # make sure the user isn't underage and trying to join an adult community
        return 0 unless $u->can_join_adult_comm( comm => $tu );

        # the community must be open membership
        return 0 unless $tu->is_open_membership;
    }

    # okay, good to go!
    return 1;
}
*LJ::User::can_join = \&can_join;


1;
