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
        return (
            LJ::Support::has_any_support_priv( $_[0]->{remote} ),
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

sub recent_comments_controller {
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:commentview', 'siteadmin:*' ] );
    return $rv unless $ok;

    my $scope = '/admin/recent_comments.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->get_args;
    my $vars      = {};

    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;

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

    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;

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
