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
use DW::User::Edges;

# membership edges are for someone who is a member of a community
DW::User::Edges::define_edge(
    member => {
        type    => 'hashref',
        db_edge => 'E',
        options => {
            moderated_add => { required => 0, type => 'bool', default => 0 },
        },
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
    my $member_edge = delete $edges->{member}
        or return;

    # error check adding an edge
    return 0
        unless $from_u->can_join( $to_u, moderated_add => $member_edge->{moderated_add} ? 1 : 0 );

    # simply add the reluser edge
    my $rv = LJ::set_rel( $to_u, $from_u, 'E' );

    # delete memcache key for community reading pages
    LJ::memcache_kill( $to_u, 'c_wt_list' );

    # success?
    return $rv;
}

# internal method to delete an edge
sub _del_m_edge {
    my ( $from_u, $to_u, $edges ) = @_;
    $from_u = LJ::want_user($from_u) or return 0;
    $to_u   = LJ::want_user($to_u)   or return 0;

    # same logic as in _add_m_edge
    delete $edges->{member}
        or return;

    # now remove it; note we don't do any extraneous checking.  if the user
    # wants to remove an edge that doesn't exist?  more power to them.
    LJ::clear_rel( $to_u, $from_u, 'E' );

    # delete memcache key for community reading pages
    LJ::memcache_kill( $to_u, 'c_wt_list' );

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
    $from_u = LJ::want_user($from_u) or return 0;
    $to_u   = LJ::want_user($to_u)   or return 0;

    # individual->comm
    return 0
        unless $from_u->is_individual
        && $to_u->is_community;

    # check it
    return 1 if LJ::check_rel( $to_u, $from_u, 'E' );
    return 0;
}
*LJ::User::member_of = \&member_of;

# returns array of userids we're member of
sub member_of_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user($u) or return ();

    return ()
        unless $u->is_individual;

    return @{ LJ::load_rel_target_cache( $u, 'E' ) || [] };
}
*LJ::User::member_of_userids = \&member_of_userids;

# returns array of userids that are our members
sub member_userids {
    my ( $u, %args ) = @_;
    $u = LJ::want_user($u) or return ();

    return ()
        unless $u->is_community;

    return @{ LJ::load_rel_user_cache( $u, 'E' ) || [] };
}
*LJ::User::member_userids = \&member_userids;

# returns 1/0 depending on if the source is allowed to add a member edge
# to the target.  note: if you don't pass a target user, then we return
# a generic 1/0 meaning "this account is allowed to have a member edge".
sub can_join {
    my ( $u, $tu, %opts ) = @_;
    $u  = LJ::want_user($u) or confess 'invalid user object';
    $tu = LJ::want_user($tu);

    my $errref         = $opts{errref};
    my $membership_ref = $opts{membership_ref};
    my $moderated_add  = $opts{moderated_add} ? 1 : 0;

    # if the user is a maintainer, skip every other check
    return 1 if $tu && $u->can_manage($tu);

    # the user must be a personal account or identity account
    unless ( $u->is_individual ) {
        $$errref = LJ::Lang::ml('edges.join.error.usernotindividual');
        return 0;
    }

    # the user must be visible
    unless ( $u->is_visible ) {
        $$errref = LJ::Lang::ml('edges.join.error.usernotvisible');
        return 0;
    }

    if ($tu) {

        # the target must be a community
        unless ( $tu->is_community ) {
            $$errref = LJ::Lang::ml('edges.join.error.targetnotcommunity');
            return 0;
        }

        # the target must be visible
        unless ( $tu->is_visible ) {
            $$errref = LJ::Lang::ml('edges.join.error.targetnotvisible');
            return 0;
        }

        # the target must not have banned the user
        if ( $tu->has_banned($u) ) {
            $$errref = LJ::Lang::ml('edges.join.error.targetbanneduser');
            return 0;
        }

        # make sure the user isn't underage and trying to join an adult community
        my $adult_content;
        unless ( $u->can_join_adult_comm( comm => $tu, adultref => \$adult_content ) ) {
            if ( $adult_content eq "explicit" ) {
                $$errref = LJ::Lang::ml('edges.join.error.userunderage');
            }

            unless ( $u->best_guess_age ) {
                $$errref .= " "
                    . LJ::Lang::ml( 'edges.join.error.setage',
                    { url => LJ::create_url("/manage/profile/") } );
            }

            return 0;
        }

        # the community must be open membership or we must be adding to a moderated community
        unless ( $tu->is_open_membership || $opts{moderated_add} ) {
            $$errref         = LJ::Lang::ml('edges.join.error.targetnotopen');
            $$membership_ref = 1;
            return 0;
        }
    }

    # okay, good to go!
    return 1;
}
*LJ::User::can_join = \&can_join;

# returns 1/0 depending on if the source is allowed to remove a member edge
# from the target.  note: if you don't pass a target user, then we return
# a generic 1/0 meaning "this account is allowed to not have a member edge".
sub can_leave {
    my ( $u, $tu, %opts ) = @_;
    $u  = LJ::want_user($u) or confess 'invalid user object';
    $tu = LJ::want_user($tu);

    my $errref = $opts{errref};

    # if the user is the last maintainer, they can't leave
    if ($tu) {
        my @maintids    = $tu->maintainer_userids;
        my $ismaint     = grep { $_ == $u->id } @maintids;
        my $othermaints = grep { $_ != $u->id } @maintids;

        if ( $ismaint && !$othermaints ) {
            if ( $tu->is_deleted ) {

                # one exception: maintainer can remove themselves from a deleted community
                return 1;
            }
            else {
                $$errref = LJ::Lang::ml(
                    'edges.leave.error.lastmaintainer2',
                    { url => $tu->community_manage_members_url }
                );
                return 0;
            }
        }
    }

    # okay, good to go!
    return 1;
}
*LJ::User::can_leave = \&can_leave;

1;
