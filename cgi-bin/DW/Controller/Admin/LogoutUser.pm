#!/usr/bin/perl
#
# DW::Controller::Admin::LogoutUser
#
# Expires sessions of a user
#
# Authors:
#      foxfirefey <foxfirefey@gmail.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::LogoutUser;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use LJ::User;

my $privs = ['suspend'];

DW::Routing->register_string( "/admin/logout_user", \&index_controller );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'logout_user',
    ml_scope => '/admin/logout_user.tt',
    privs    => $privs,
);

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => $privs );
    return $rv unless $ok;

    my $vars = {%$rv};
    my $r    = DW::Request->get;
    my @errors;
    $vars->{u} = 0;    # otherwise, page automatically loads the remote

    if ( $r->did_post ) {
        return DW::Template->render_template( 'error.tt', { "message" => "Invalid form auth" } )
            unless LJ::check_form_auth( $r->post_args->{lj_form_auth} );

        my $u;
        my $user = LJ::ehtml( $r->post_args->{user} );

        if ( $r->post_args->{user} ) {
            $u = LJ::load_user_or_identity( $r->post_args->{user} );
            $vars->{user} = $user;
        }

        push @errors, "Unknown user: $user" unless $u;

        if ($u) {
            push @errors, "Deleted and purged user: $user"
                if $u->is_expunged;    # notify of this but still expire sessions
            push @errors, "User is a community: " . LJ::ljuser($u) if $u->is_community;
            push @errors, "User is a feed: " . LJ::ljuser($u)      if $u->is_syndicated;

            if ( $u->is_personal || $u->is_identity ) {  # these are the account types with sessions
                my $remote   = LJ::get_remote();
                my $udbh     = LJ::get_cluster_master($u);
                my $sessions = $udbh->selectcol_arrayref(
                    "SELECT sessid FROM sessions WHERE " . "userid=$u->{userid}" );
                $u->kill_sessions(@$sessions) if @$sessions;
                my $ct = scalar(@$sessions);

                LJ::statushistory_add( $u->{userid}, $remote->{userid}, 'logout_user',
                    "expired $ct sessions" );
                $vars->{sessions} = $sessions;
                $vars->{u}        = $u;
            }
        }

    }

    $vars->{error_list} = \@errors if @errors;
    return DW::Template->render_template( 'admin/logout_user.tt', $vars );
}

1;
