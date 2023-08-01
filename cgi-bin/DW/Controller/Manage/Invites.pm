#!/usr/bin/perl
#
# DW::Controller::Manage::Invites
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#

package DW::Controller::Manage::Invites;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/invites", \&invites_handler, app => 1 );

sub invites_handler {
    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};
    return DW::Template->render_template( 'error.tt', { message => $LJ::MSG_READONLY_USER } )
        if $u->is_readonly;

    # get pending invites
    my $pending = $u->get_pending_invites || [];

    # all possible invitation attributes
    my @allattribs = ( 'member', 'post', 'preapprove', 'moderate', 'admin' );

    # load communities and maintainers
    my @ids;
    push @ids, ( $_->[0], $_->[1] ) foreach @$pending;
    my $us = LJ::load_userids(@ids);

    if ( $r->did_post ) {
        my ( @accepted, @rejected, @undecided );

        foreach my $invite (@$pending) {
            my ( $commid, $maintid, $_date, $argline ) = @$invite;
            my $args = {};
            LJ::decode_url_string( $argline, $args );
            my $cu = $us->{$commid};
            next unless $cu;

            my $response = $r->post_args->{"pending_$commid"} // '';

            # now take actions?
            if ( $response eq 'yes' ) {
                if ( $u->accept_comm_invite($cu) ) {
                    push @accepted, [ $cu, [ grep { $args->{$_} } @allattribs ] ];
                    $cu->notify_administrator_add( $u, $us->{$maintid} ) if $args->{admin};
                }
            }
            elsif ( $response eq 'no' ) {
                push @rejected, $cu if $u->reject_comm_invite($cu);
            }
            else {
                push @undecided, $cu;
            }
        }

        $rv->{responses} =
            { accepted => \@accepted, rejected => \@rejected, undecided => \@undecided };

        return DW::Template->render_template( 'manage/invites.tt', $rv );
    }

    my @invites;

    foreach my $invite (@$pending) {
        my ( $commid, $maintid, $date, $argline ) = @$invite;
        my $args = {};
        LJ::decode_url_string( $argline, $args );
        my $cu = $us->{$commid};
        next unless $cu;

        my $inv = {
            cu   => $cu,
            mu   => $us->{$maintid},
            key  => "pending_$commid",
            tags => [ grep { $args->{$_} } @allattribs ],
            date => LJ::mysql_time($date),
        };
        push @invites, $inv;
    }

    $rv->{invites} = \@invites;

    return DW::Template->render_template( 'manage/invites.tt', $rv );
}

1;
