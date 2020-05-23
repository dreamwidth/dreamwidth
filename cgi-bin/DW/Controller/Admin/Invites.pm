#!/usr/bin/perl
#
# DW::Controller::Admin::Invites
#
# Management tasks related to invite codes.
# Requires finduser:codetrace, siteadmin:invites, or payments privileges.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::Invites;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use DW::InviteCodes;

my $invite_privs =
    [ 'finduser:codetrace', 'finduser:*', 'payments', 'siteadmin:invites', 'siteadmin:*' ];

DW::Routing->register_string( "/admin/invites", \&index_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'invites',
    ml_scope => '/admin/invites/index.tt',
    privs    => $invite_privs
);

DW::Routing->register_string( "/admin/invites/codetrace", \&codetrace_controller, app => 1 );

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => $invite_privs );
    return $rv unless $ok;
    my $remote = $rv->{remote};

    # we show links to various subpages depending on which privs the remote has;
    # can_manage_invites_light consists of "payments" or "siteadmin:invites"

    my $vars = {
        has_payments => $remote->has_priv("payments"),
        has_finduser => $remote->has_priv( "finduser", "codetrace" ),
        has_invites  => $remote->can_manage_invites_light,
    };

    return DW::Template->render_template( 'admin/invites/index.tt', $vars );
}

sub codetrace_controller {
    my ( $ok, $rv ) = controller( privcheck => [ 'finduser:codetrace', 'finduser:*' ] );
    return $rv unless $ok;

    my $scope = '/admin/invites/codetrace.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->get_args;
    my $vars      = {};

    my $account;

    if ( $form_args->{code} ) {
        if ( my $code = DW::InviteCodes->new( code => $form_args->{code} ) ) {
            $account = $rv->{remote};
            $vars->{display_codes} = [$code];

        }
        else {
            $vars->{display_error} =
                LJ::Lang::ml( "$scope.error.invalidcode", { code => $form_args->{code} } );
        }

    }
    elsif ( $form_args->{account} ) {
        if ( $account = LJ::load_user( $form_args->{account} ) ) {
            my @used  = DW::InviteCodes->by_recipient( userid => $account->id );
            my @owned = DW::InviteCodes->by_owner( userid => $account->id );

            if ( @used or @owned ) {
                $vars->{display_codes} = [ @used, @owned ];
            }
            else {
                $vars->{display_error} =
                    LJ::Lang::ml( "$scope.error.nocodes", { account => $account->ljuser_display } );
            }

        }
        else {
            $vars->{display_error} =
                LJ::Lang::ml( "$scope.error.invaliduser", { user => $form_args->{account} } );
        }

    }

    $vars->{maxlength_code} = DW::InviteCodes::CODE_LEN;
    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;
    $vars->{time_to_http}   = sub { return LJ::time_to_http( $_[0] ) };

    $vars->{load_code_owner} = sub {
        return $_[0]->owner == $account->id ? $account : LJ::load_userid( $_[0]->owner );
    };

    $vars->{load_code_recipient} = sub {
        return $_[0]->is_used ? LJ::load_userid( $_[0]->recipient ) : undef;
    };

    return DW::Template->render_template( 'admin/invites/codetrace.tt', $vars );
}

1;
