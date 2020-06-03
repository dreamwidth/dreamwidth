#!/usr/bin/perl
#
# DW::Controller::Admin::Sysban
#
# Frontend for managing/setting/clearing sysbans.
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

package DW::Controller::Admin::Sysban;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use LJ::Sysban;

DW::Routing->register_string( "/admin/sysban", \&sysban_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'sysban',
    ml_scope => '/admin/sysban/index.tt',
    privs    => ['sysban']
);

sub sysban_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['sysban'] );
    return $rv unless $ok;

    my $scope = '/admin/sysban/index.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->post_args;
    my $vars      = {};

    {    # construct sorted list of sysban privs visible to remote

        my $remote = $rv->{remote};
        my @sysban_privs;

        my @all_sb_args = LJ::list_valid_args('sysban');
        my %priv_args   = $remote->priv_args('sysban');

        foreach my $arg ( sort keys %priv_args ) {
            if ( $arg eq '*' ) {
                @sysban_privs = sort @all_sb_args;
                last;
            }
            else {
                push @sysban_privs, $arg;
            }
        }

        $vars->{sysban_privs} = \@sysban_privs;
        $vars->{sysban_menu}  = [ map { $_, $_ } @sysban_privs ];
    }

    return DW::Template->render_template( 'admin/sysban/index.tt', $vars )
        unless $r->did_post;

    $vars->{formdata} = $form_args;

    # make sure we were given an action to handle

    ( $vars->{action} ) = grep { $form_args->{$_} } qw( add addnew modify query queryone );

    return error_ml("$scope.error.noaction") unless $vars->{action};

    $vars->{localtime} = sub { scalar localtime( $_[0] ) };

    if ( $vars->{action} eq 'addnew' ) {

        return DW::Template->render_template( 'admin/sysban/addnew.tt', $vars );
    }

    if ( $vars->{action} eq 'query' ) {

        $vars->{skip}  = $form_args->{skip} || 0;
        $vars->{limit} = 20;

        my $existing_bans = {};

        LJ::Sysban::populate_full( $existing_bans, $form_args->{bantype}, $vars->{limit},
            $vars->{skip} );

        $vars->{existing_bans} = $existing_bans;

        return DW::Template->render_template( 'admin/sysban/query.tt', $vars );
    }

    if ( $vars->{action} eq 'modify' ) {    # this action comes from the query form

        my $modify = LJ::Sysban::modify(
            banid   => $form_args->{banid},
            expire  => $form_args->{expire},
            bandays => $form_args->{bandays},
            note    => $form_args->{note},
            what    => $form_args->{bantype},
            value   => $form_args->{value},
        );

        return error_ml( "$scope.error.modify", { message => $modify->{message} } )
            if ( ref $modify eq 'ERROR' );

        return success_ml(
            "$scope.success.modify",
            undef,
            [
                {
                    text => LJ::Lang::ml("$scope.success.linktext"),
                    url  => '/admin/sysban'
                }
            ]
        );
    }

    if ( $vars->{action} eq 'add' ) {    # this action comes from the addnew form

        my $bantype = $form_args->{bantype};
        my $remote  = $rv->{remote};

        return error_ml( "$scope.error.nopriv", { bantype => $bantype } )
            unless $remote->has_priv( 'sysban', $bantype );

        return error_ml("$scope.error.nonote") unless $form_args->{note};

        # trim whitespace from both ends of the input before storing it in $value
        my $value = LJ::trim( $form_args->{value} );

        # force_spelling is used by LJ::check_email inside the validate function

        my $notvalid = LJ::Sysban::validate( $bantype, $value, undef, $form_args );

        return error_ml( "$scope.error.notvalid", { reason => $notvalid } ) if $notvalid;

        my $create = LJ::Sysban::create(
            what    => $bantype,
            value   => $value,
            bandays => $form_args->{bandays},
            note    => $form_args->{note},
        );

        return error_ml( "$scope.error.create", { message => $create->{message} } )
            if ( ref $create eq 'ERROR' );

        return success_ml(
            "$scope.success.create",
            undef,
            [
                {
                    text => LJ::Lang::ml("$scope.success.linktext"),
                    url  => '/admin/sysban'
                }
            ]
        );
    }

    if ( $vars->{action} eq 'queryone' ) {

        # these results are displayed within the index form

        $vars->{sysbans} = LJ::Sysban::populate_full_by_value( $form_args->{queryvalue},
            @{ $vars->{sysban_privs} } );
    }

    return DW::Template->render_template( 'admin/sysban/index.tt', $vars );
}

1;
