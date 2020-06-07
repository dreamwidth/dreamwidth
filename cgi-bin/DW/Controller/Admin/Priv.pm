#!/usr/bin/perl
#
# DW::Controller::Admin::Priv
#
# Manage privileges for a given user, or see who has a given privilege.
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

package DW::Controller::Admin::Priv;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'priv/',
    ml_scope => '/admin/priv/index.tt',

    # ironically the privs page has no check for privs, it's public
);

DW::Routing->register_string( "/admin/priv/index", \&main_controller, app => 1 );

sub main_controller {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = {};

    my $scope = '/admin/priv/index.tt';

    my $remote = $rv->{remote};

    # see which privileges remote can grant
    $remote->load_user_privs('admin');

    # returns true if the remote user can grant the given priv
    $vars->{remote_can_grant} = sub {
        my ( $priv, $arg ) = @_;
        return 0 unless $priv;
        return $remote->has_priv( 'admin', "$priv/$arg" ) if $arg;
        return $remote->has_priv( 'admin', $priv );
    };

    # load all privilege info from the database

    my $dbh = LJ::get_db_writer();

    $vars->{privs} = $dbh->selectall_arrayref(
        "SELECT prlid, privcode, privname, des, is_public, scope "
            . "FROM priv_list ORDER BY privcode",
        { Slice => {} }
    );

    $vars->{priv_by_id} = {};
    $vars->{map_codeid} = {};

    foreach ( @{ $vars->{privs} } ) {
        $vars->{priv_by_id}->{ $_->{prlid} }    = $_;
        $vars->{map_codeid}->{ $_->{privcode} } = $_->{prlid};
    }

    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;

    my $mode = $form_args->{mode};

    $mode ||= "viewpriv" if $form_args->{priv};
    $mode ||= "viewuser" if $form_args->{user};

    return DW::Template->render_template( 'admin/priv/index.tt', $vars )
        unless $mode;

    # toggle for switching to relevant display-only mode
    my $switch_to_view_mode = sub {
        $mode = { userchange => 'viewuser', privchange => 'viewpriv' }->{$mode};
    };

    $switch_to_view_mode->() if $form_args->{'submit:refresh'};    # no changes

    if ( $mode eq "userchange" || $mode eq "privchange" ) {

        return error_ml("$scope.error.needpost") unless $r->did_post;

        my $remote_can_grant = $vars->{remote_can_grant};
        my $map_codeid       = $vars->{map_codeid};

        my $errors  = DW::FormErrors->new;
        my $success = DW::FormErrors->new;

        foreach my $key ( keys %$form_args ) {
            next unless $key =~ /^revoke:(\d+):(\d+)$/;
            my ( $prmid, $del_userid1 ) = ( $1, $2 );

            my ( $del_userid2, $prlid, $arg ) =
                $dbh->selectrow_array( "SELECT userid, prlid, arg FROM priv_map WHERE prmid=?",
                undef, $prmid );

            my $privcode = $vars->{priv_by_id}->{$prlid}->{privcode};

            if ( !$remote_can_grant->( $privcode, $arg ) ) {
                $errors->add( '', '.error.access.remove', { privcode => $privcode } );
            }
            elsif ( $del_userid1 == $del_userid2 ) {
                $dbh->do("DELETE FROM priv_map WHERE prmid=$prmid");
                LJ::statushistory_add( $del_userid1, $remote->userid, "privdel",
                    sprintf( 'Denying: "%s" with arg "%s"', $privcode, $arg || '' ) );
                $success->add( '', '.success.remove' );
            }
        }

        # these actions are the same on both sides, just different data sources
        my $process_grant = sub {
            my ( $user, $privid ) = @_;

            my $u = LJ::load_user($user);
            return error_ml("$scope.error.invaliduser") unless $u;

            my $privcode = $vars->{priv_by_id}->{$privid}->{privcode};
            my $arg      = $form_args->{arg};
            my $pname    = join( ' ', grep { $_ } $privcode, $arg );

            if ( !$privcode ) {
                $errors->add( '', '.error.unknownpriv' );
            }
            elsif ( !$remote_can_grant->( $privcode, $arg ) ) {
                $errors->add( '', '.error.access.grant', { privcode => $pname } );
            }
            elsif ( $u->has_priv( $privcode, $arg ) ) {
                $errors->add( '', '.error.already', { privcode => $pname } );
            }
            else {
                $dbh->do( "INSERT INTO priv_map (prmid, userid, prlid, arg) VALUES (NULL, ?, ?, ?)",
                    undef, $u->userid, $privid, $arg );
                LJ::statushistory_add( $u->userid, $remote->userid, "privadd",
                    sprintf( 'Granting: "%s" with arg "%s"', $privcode, $arg || '' ) );
                $success->add( '', '.success.grant', { privcode => $pname } );
            }
        };

        $process_grant->( $form_args->{user}, $form_args->{grantpriv} + 0 )
            if $form_args->{grantpriv};

        $process_grant->( $form_args->{grantuser}, $map_codeid->{ $form_args->{priv} } )
            if $form_args->{grantuser};

        $vars->{errors}  = $errors;
        $vars->{success} = $success;

        # continue executing related display code below
        $switch_to_view_mode->();
    }

    if ( $mode eq "viewuser" ) {

        my $user = LJ::canonical_username( $form_args->{user} );
        $vars->{u} = LJ::load_user($user);

        return error_ml("$scope.error.invaliduser") unless $vars->{u};

        $vars->{remote} = $remote;

        $vars->{userprivs} = $dbh->selectall_arrayref(
            "SELECT pm.prmid, pm.prlid, pm.arg FROM priv_map pm, priv_list pl"
                . " WHERE pm.prlid=pl.prlid AND pm.userid=?"
                . " ORDER BY pl.privcode, pm.arg",
            { Slice => {} },
            $vars->{u}->id,
        );

        my @privmenu = ( '', '' );
        push( @privmenu, $_->{prlid}, $_->{privcode} ) foreach @{ $vars->{privs} };
        $vars->{privmenu} = \@privmenu;

        return DW::Template->render_template( 'admin/priv/viewuser.tt', $vars );
    }

    if ( $mode eq "viewpriv" ) {

        my $privid = $vars->{map_codeid}->{ $form_args->{priv} };

        return error_ml("$scope.error.invalidpriv") unless $privid;

        $vars->{arg} = $form_args->{viewarg};

        my $qarg = '';
        $qarg = "AND pm.arg=" . $dbh->quote( $vars->{arg} ) if $vars->{arg};

        $vars->{skip}  = $form_args->{skip} || 0;
        $vars->{limit} = 100;

        $vars->{privusers} = $dbh->selectall_arrayref(
            "SELECT pm.prmid, u.user, u.userid, pm.arg FROM priv_map pm, useridmap u"
                . " WHERE pm.prlid=? AND pm.userid=u.userid $qarg"
                . " ORDER BY u.user, pm.arg LIMIT ?, ?",
            { Slice => {} }, $privid, $vars->{skip}, $vars->{limit},
        );

        $vars->{pinfo} = $vars->{priv_by_id}->{$privid};
        $vars->{pcode} = $vars->{pinfo}->{privcode};
        $vars->{pname} = join( ' ', grep { $_ } $vars->{pcode}, $vars->{arg} );

        return DW::Template->render_template( 'admin/priv/viewpriv.tt', $vars );
    }

    # if we get here, there was a problem
    return error_ml('error.invalidform');
}

1;
