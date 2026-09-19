#!/usr/bin/perl
#
# DW::Controller::Admin::UserViews
#
# Miscellaneous admin pages for viewing user data on the site.
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

package DW::Controller::Admin::UserViews;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

use LJ::S2;
use LJ::Support;
use LJ::Talk;
use DW::Auth::Password;

my $styleinfo_privs = [
    sub {
        my $remote = LJ::isu( $_[0] ) ? $_[0] : $_[0]->{remote};
        return (
            LJ::Support::has_any_support_priv($remote),
            LJ::Lang::ml("/admin/index.tt.anysupportpriv")
        );
    },
    sub {
        return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
    }
];

DW::Routing->register_string( "/admin/styleinfo", \&styleinfo_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'styleinfo',
    ml_scope => '/admin/styleinfo.tt',
    privs    => $styleinfo_privs
);

DW::Routing->register_string( "/admin/recent_comments", \&recent_comments_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'recent_comments',
    ml_scope => '/admin/recent_comments.tt',
    privs    => [ 'siteadmin:commentview', 'siteadmin:*' ]
);

DW::Routing->register_string( "/admin/impersonate", \&impersonate_controller, app => 1 );

# The impersonate page isn't listed in the index because the index is public
# and seeing it listed there makes people nervous that we use it all the time,
# which we don't. It's not a secret but we don't advertise it.

sub impersonate_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => ['canview:*'] );
    return $rv unless $ok;

    my $r         = DW::Request->get;
    my $form_args = $r->post_args;
    my $vars      = {};

    my $errors = DW::FormErrors->new;

    if ( $r->did_post && LJ::check_referer('/admin/impersonate') ) {

        my $remote = $rv->{remote};

        my $u = LJ::load_user( $form_args->{username} );
        $errors->add( 'username', '.error.invaliduser',
            { user => LJ::ehtml( $form_args->{username} ) } )
            unless $u;

        # Impersonation is not a second-factor bypass. Reject protected targets
        # before replacing the administrator's current session.
        require DW::Auth::TOTP;
        $errors->add_string( 'username',
            'Accounts protected by two-factor authentication cannot be impersonated.' )
            if $u && DW::Auth::TOTP->is_enabled($u);

        my $password = $form_args->{password};
        $errors->add( 'password', '.error.invalidpassword' )
            unless $password && DW::Auth::Password->check( $remote, $password );

        my $reason = LJ::ehtml( LJ::trim( $form_args->{reason} ) );
        $errors->add( 'reason', '.error.emptyreason' ) unless $reason;

        unless ( $errors->exist ) {

            my $dbh = LJ::get_db_writer() or die 'Database unavailable';
            $dbh->begin_work or die $dbh->errstr;
            my ( $protected, $invalid_password );
            my $previous_session = $u->{_session};
            my $session;
            my $admin_session = $remote->session;
            my $publishing;
            my @cookies      = $r->err_header_out('Set-Cookie');
            my $impersonated = eval {
                for my $userid ( sort { $a <=> $b } ( $u->id, $remote->id ) ) {
                    $dbh->selectrow_array(
                        'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
                        undef, $userid );
                    die $dbh->errstr if $dbh->err;
                }
                if ( DW::Auth::TOTP->is_enabled($u) ) {
                    $protected = 1;
                    $dbh->rollback;
                    0;
                }
                elsif ( !DW::Auth::Password->check( $remote, $password ) ) {
                    $invalid_password = 1;
                    $dbh->rollback;
                    0;
                }
                else {
                    $session =
                        LJ::Session->create( $u, exptype => 'once', nolog => 1, defer_login => 1 )
                        or die 'Unable to create impersonation session';
                    $u->{_session} = $previous_session;
                    $dbh->commit or die $dbh->errstr;
                    my $current = LJ::Session->instance( $u, $session->id );
                    die 'Impersonation session revoked' unless $current && $current->valid;
                    $publishing = 1;
                    $u->publish_login_session( $session, 1 )
                        or die 'Unable to publish impersonation session';
                    1;
                }
            };
            if ($@) {
                my $error = $@;
                $dbh->rollback unless $dbh->{AutoCommit};
                eval { $session->destroy } if $session;
                $u->{_session} = $previous_session;
                if ($publishing) {

                    # Discard every target cookie, including trust and scheme
                    # cookies, while preserving headers set before publication.
                    $r->err_header_out( 'Set-Cookie', \@cookies );
                    LJ::User->set_remote($remote);
                }
                die $error;
            }
            if ($impersonated) {

                # Publication succeeded. A cleanup failure must not discard the
                # usable target session and try to restore an already deleted one.
                if ($admin_session) {
                    eval { $admin_session->destroy
                            or die 'Unable to revoke administrator session' };
                    warn "Impersonator session cleanup failed: $@" if $@;
                }

                # log for auditing
                $remote->log_event( 'impersonator',
                    { actiontarget => $u->id, remote => $remote, reason => $reason } );
                $u->log_event( 'impersonated',
                    { actiontarget => $u->id, remote => $remote, reason => $reason } );
                LJ::statushistory_add( $u->id, $remote->id, 'impersonate', $reason );

                return $r->redirect($LJ::SITEROOT);
            }
            else {
                $protected
                    ? $errors->add_string( 'username',
                    'Accounts protected by two-factor authentication cannot be impersonated.' )
                    : $invalid_password ? $errors->add( 'password', '.error.invalidpassword' )
                    :                     $errors->add( '', '.error.failedlogin' );
            }
        }
    }

    $vars->{errors}   = $errors;
    $vars->{formdata} = $form_args;

    return DW::Template->render_template( 'admin/impersonate.tt', $vars );
}

sub recent_comments_controller {
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:commentview', 'siteadmin:*' ] );
    return $rv unless $ok;

    my $scope = '/admin/recent_comments.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->get_args;
    my $vars      = {};

    if ( my $user = $form_args->{user} ) {
        $vars->{u} = ( $user =~ /^\#(\d+)/ ) ? LJ::load_userid($1) : LJ::load_user($user);
        return error_ml("$scope.error.invaliduser") unless $vars->{u};
    }
    else {
        return DW::Template->render_template( 'admin/recent_comments.tt', $vars );
    }

    my $now = time();
    $vars->{num_hours} = sub { sprintf( "%.1f", ( $now - $_[0] ) / 3600 ) };

    $vars->{get_journal} = sub { LJ::load_userid( $_[0]->{journalid} ) };
    $vars->{get_comment} = sub { LJ::get_log2_row( $_[1], $_[0]->{nodeid} ) };

    $vars->{talklink} = sub {
        my ( $lrow, $r, $ju ) = @_;
        return unless $lrow;
        my $talkid  = ( $r->{jtalkid} << 8 ) + $lrow->{anum};
        my $talkurl = $ju->journal_base . "/$lrow->{ditemid}.html";
        return LJ::Talk::talkargs( $talkurl, "thread=$talkid" ) . LJ::Talk::comment_anchor($talkid);
    };

    my $dbcr = LJ::get_cluster_reader( $vars->{u} );
    return error_ml("$scope.error.nodb") unless $dbcr;

    $vars->{rows} = $dbcr->selectall_arrayref(
        "SELECT posttime, journalid, nodetype, nodeid, jtalkid, publicitem "
            . "FROM talkleft WHERE userid=? ORDER BY posttime DESC LIMIT 250",
        { Slice => {} },
        $vars->{u}->id
    );

    return DW::Template->render_template( 'admin/recent_comments.tt', $vars );
}

sub styleinfo_controller {
    my ( $ok, $rv ) = controller( privcheck => $styleinfo_privs );
    return $rv unless $ok;

    my $scope = '/admin/styleinfo.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = {};

    $vars->{formdata} = $form_args;

    return DW::Template->render_template( 'admin/styleinfo.tt', $vars )
        unless $form_args->{user};

    $vars->{u} = LJ::load_user( $form_args->{user} );

    return error_ml( "$scope.error.nouser", { user => $form_args->{user} } )
        unless $vars->{u};

    return error_ml( "$scope.error.purged", { user => $form_args->{user} } )
        if $vars->{u}->is_expunged;

    return error_ml("$scope.error.s1") unless $vars->{u}->prop("stylesys") == 2;

    if ( my $u_style = $vars->{u}->prop("s2_style") ) {
        $vars->{s2style} = LJ::S2::load_style($u_style);
        $vars->{public}  = LJ::S2::get_public_layers();
    }

    $vars->{mysql_time} = sub { $_[0] ? LJ::mysql_time( $_[0] ) : "" };
    $vars->{sort_keys}  = sub {
        [ sort { $a cmp $b } keys %{ $_[0] } ]
    };

    return DW::Template->render_template( 'admin/styleinfo.tt', $vars );
}

1;
