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
    privs    => [ 'sysban', 'sysbanview' ]
);

sub sysban_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => [ 'sysban', 'sysbanview' ] );
    return $rv unless $ok;

    my $scope = '/admin/sysban/index.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->post_args;
    my $vars      = {};

    my $remote = $rv->{remote};
    my %read_args = ( $remote->priv_args('sysban'), $remote->priv_args('sysbanview') );
    my %write_args = $remote->priv_args('sysban');
    my @all_sb_args = LJ::list_valid_args('sysban');
    my @sysban_privs = sort grep { length } ( $read_args{'*'} ? @all_sb_args : keys %read_args );
    my @write_privs = sort grep { length } ( $write_args{'*'} ? @all_sb_args : keys %write_args );

    $vars->{sysban_privs} = \@sysban_privs;
    $vars->{sysban_menu} = [ map { $_, $_ } @sysban_privs ];
    $vars->{can_add} = scalar @write_privs;

    return DW::Template->render_template( 'admin/sysban/index.tt', $vars )
        unless $r->did_post;

    $vars->{formdata} = $form_args;

    # make sure we were given an action to handle

    ( $vars->{action} ) = grep { $form_args->{$_} } qw( add addnew modify query queryone );

    return error_ml("$scope.error.noaction") unless $vars->{action};

    $vars->{localtime} = sub { scalar localtime( $_[0] ) };

    my $bantype = $form_args->{bantype};
    if ( $vars->{action} eq 'query' ) {
        return error_ml( "$scope.error.nopriv", { bantype => $bantype } )
            unless length( $bantype || '' )
            && ( $remote->has_priv( 'sysban', $bantype )
                || $remote->has_priv( 'sysbanview', $bantype ) );
        $vars->{can_modify} = $remote->has_priv( 'sysban', $bantype );
    }
    elsif ( $vars->{action} eq 'addnew' ) {
        return error_ml( "$scope.error.nopriv", { bantype => $bantype } ) unless @write_privs;
    }
    elsif ( $vars->{action} ne 'queryone' ) {
        return error_ml( "$scope.error.nopriv", { bantype => $bantype } )
            unless length( $bantype || '' ) && $remote->has_priv( 'sysban', $bantype );
    }

    if ( $vars->{action} eq 'addnew' ) {

        $vars->{sysban_menu} = [ map { $_, $_ } @write_privs ];
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

        # The hidden type is not authoritative: the ban ID must belong to that type.
        my $stored_type = LJ::get_db_writer()->selectrow_array(
            "SELECT what FROM sysban WHERE banid = ?", undef, $form_args->{banid}
        );
        return error_ml( "$scope.error.nopriv", { bantype => $bantype } )
            unless defined $stored_type && $stored_type eq $bantype;

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

        return DW::Controller->render_success( 'admin/sysban/query.tt', undef,
            [ { text_ml => '.success.linktext', url => '/admin/sysban' } ] );
    }

    if ( $vars->{action} eq 'add' ) {    # this action comes from the addnew form

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

        return DW::Controller->render_success( 'admin/sysban/addnew.tt', undef,
            [ { text_ml => '.success.linktext', url => '/admin/sysban' } ] );
    }

    if ( $vars->{action} eq 'queryone' ) {

        # An empty type list means all types to the lookup helper, so fail closed.
        return error_ml( "$scope.error.nopriv", { bantype => '' } ) unless @sysban_privs;

        # these results are displayed within the index form

        my $lookup =
            $form_args->{expiredcheck}
            ? sub { LJ::Sysban::populate_full_by_value_with_expired(@_) }
            : sub { LJ::Sysban::populate_full_by_value(@_) };

        $vars->{sysbans} = $lookup->( $form_args->{queryvalue}, @{ $vars->{sysban_privs} } );
    }

    return DW::Template->render_template( 'admin/sysban/index.tt', $vars );
}

1;
