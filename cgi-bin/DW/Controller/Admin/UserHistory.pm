#!/usr/bin/perl
#
# DW::Controller::Admin::UserHistory
#
# Admin pages for userlog and statushistory, converted from LJ.
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

package DW::Controller::Admin::UserHistory;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

my $statushistory_privs = [
    'historyview',
    sub {
        return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
    }
];

DW::Routing->register_string( "/admin/statushistory", \&statushistory_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'statushistory',
    ml_scope => '/admin/statushistory.tt',
    privs    => $statushistory_privs
);

DW::Routing->register_string( "/admin/userlog", \&userlog_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'userlog',
    ml_scope => '/admin/userlog.tt',
    privs    => [ 'canview:userlog', 'canview:*' ]
);

sub statushistory_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => $statushistory_privs );
    return $rv unless $ok;

    my $scope = '/admin/statushistory.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = {};

    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;

    $vars->{formdata} = $form_args;
    $vars->{showtable} =
        ( $form_args->{'user'} || $form_args->{'admin'} || $form_args->{'type'} ) ? 1 : 0;

    return DW::Template->render_template( 'admin/statushistory.tt', $vars )
        unless $vars->{showtable};

    # build database query

    my $errors = DW::FormErrors->new;
    my $dbr    = LJ::get_db_reader();
    my @where;

    if ( $form_args->{'user'} ) {
        if ( my $userid = LJ::get_userid( $form_args->{'user'} ) ) {
            push @where, "s.userid=$userid";
        }
        else {
            $errors->add( "user", ".error.nouser" );
        }
    }

    if ( $form_args->{'admin'} ) {
        if ( my $userid = LJ::get_userid( $form_args->{'admin'} ) ) {
            push @where, "s.adminid=$userid";
        }
        else {
            $errors->add( "admin", ".error.noadmin" );
        }
    }

    if ( $form_args->{'type'} ) {
        my $qt = $dbr->quote( $form_args->{'type'} );
        push @where, "s.shtype=$qt";
    }

    if ( $errors->exist ) {
        $vars->{errors}    = $errors;
        $vars->{showtable} = 0;
        return DW::Template->render_template( 'admin/statushistory.tt', $vars );
    }

    my $where = "";
    $where = "WHERE " . join( " AND ", @where ) . " " if @where;

    my $orderby = 's.shdate';
    $orderby = {
        user   => "u.user",
        admin  => "admin",
        shdate => "s.shdate",
        shtype => "s.shtype",
        notes  => "s.notes",
    }->{ $form_args->{'orderby'} }
        if $form_args->{'orderby'};

    my $flow = 'DESC';
    $flow = 'ASC' if $form_args->{'flow'} && $form_args->{'flow'} eq 'asc';

    $vars->{rows} = $dbr->selectall_arrayref(
        "SELECT u.user, ua.user AS admin, s.shtype, s.shdate, s.notes "
            . "FROM statushistory s "
            . "LEFT JOIN useridmap ua ON s.adminid=ua.userid "
            . "LEFT JOIN useridmap u ON s.userid=u.userid "
            . $where
            . "ORDER BY $orderby $flow LIMIT 1000",
        { Slice => {} }
    );

    return error_ml( "$scope.error.db", { err => $dbr->errstr } ) if $dbr->err;

    $vars->{canview} = sub {
        return 1 if $LJ::IS_DEV_SERVER;

        my $remote = $rv->{remote};
        return 1 if $remote->has_priv( 'historyview', '' );

        return $remote->has_priv( 'historyview', $_[0]->{shtype} );
    };

    # I dislike using ljuser instead of ljuser_display,
    # but this flow works better for this specific case
    $vars->{ljuser} = sub { LJ::ljuser( $_[0] ) };

    $vars->{format_time} = sub {
        my $time = $_[0];
        $time =~ s/(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/$1-$2-$3 $4:$5:$6/;
        return $time;
    };

    $vars->{format_note} = sub {
        my $enotes = LJ::ehtml( $_[0] );
        $enotes =~ s!\n!<br />\n!g;
        return $enotes;
    };

    return DW::Template->render_template( 'admin/statushistory.tt', $vars );
}

sub userlog_controller {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => [ 'canview:userlog', 'canview:*' ] );
    return $rv unless $ok;

    my $scope = '/admin/userlog.tt';

    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;
    my $vars      = {};

    $vars->{maxlength_user} = $LJ::USERNAME_MAXLENGTH;

    $vars->{user} = LJ::canonical_username( $form_args->{user} );

    return DW::Template->render_template( 'admin/userlog.tt', $vars )
        unless $vars->{user};

    $vars->{u} = LJ::load_user( $vars->{user} );

    return error_ml("$scope.error.nouser") unless $vars->{u};
    return error_ml("$scope.error.purged") if $vars->{u}->is_expunged;

    my $dbcr = LJ::get_cluster_reader( $vars->{u} );
    return error_ml("$scope.error.nodb") unless $dbcr;

    $vars->{rows} = $dbcr->selectall_arrayref(
        'SELECT * FROM userlog WHERE userid = ? ORDER BY logtime DESC LIMIT 10000',
        { Slice => {} },
        $vars->{u}->id
    );

    $vars->{action_text} = sub {
        my ($row) = @_;
        my $extra = {};
        LJ::decode_url_string( $row->{extra} // '', $extra );

        my $action = $row->{action};

        # we have a lot of possible actions and this used to be a long
        # chain of elsif conditionals - hopefully breaking it into chunks
        # of similar actions will be slightly easier to maintain.

        my $ml = sub { LJ::Lang::ml( "$scope$_[0]", $_[1] ) };

        my %need_target_u =
            map { $_ => 1 }
            qw(ban_set ban_unset maintainer_add maintainer_remove impersonator screen_set screen_unset);

        if ( $need_target_u{$action} ) {
            my $u    = LJ::load_userid( $row->{actiontarget} );
            my $user = $u ? $u->ljuser_display : "userid \#$row->{actiontarget}";

            return $ml->(
                ".action.$action", { user => $user, reason => LJ::ehtml( $extra->{reason} ) }
            );
        }

        if ( $action eq 'redirect' ) {
            return $ml->( ".action.redirect.$extra->{action}", { to => $extra->{renamedto} } );
        }

        if ( $action eq 'accountstatus' ) {
            my $path = "$extra->{old} -> $extra->{new}";
            return $ml->(".action.accountstatus.V-to-D") if $path eq 'V -> D';
            return $ml->(".action.accountstatus.D-to-V") if $path eq 'D -> V';
            return $ml->( ".action.accountstatus.any",
                { old => $extra->{old}, new => $extra->{new} } );
        }

        # at this point every other valid action is straightforward

        my %other_actions = (
            account_create      => {},
            delete_entry        => { target => $row->{actiontarget}, method => $extra->{method} },
            delete_userpic      => { picid => $extra->{picid} },
            email_change        => { new => $extra->{new} },
            emailpost_auth      => {},
            emailpost           => {},
            friend_invite_sent  => { whom => $extra->{extra} },
            impersonated        => { reason => LJ::ehtml( $extra->{reason} ) },
            mass_privacy_change => { from => $extra->{s_security}, to => $extra->{e_security} },
            password_change     => {},
            password_reset      => {},
            rename              => {
                from  => $extra->{from},
                to    => $extra->{to},
                del   => $extra->{del} ? "<br />Deleted: $extra->{del}" : '',
                redir => $extra->{redir} ? "<br />Redirected: $extra->{redir}" : '',
            },
            siteadmin_email =>
                { account => $extra->{account}, domain => $LJ::DOMAIN, msgid => $extra->{msgid} },
        );

        return $ml->( ".action.$action", $other_actions{$action} )
            if exists $other_actions{$action};

        return $ml->( ".action.unknown", { action => $action } );
    };

    $vars->{load_actor} = sub { LJ::load_userid( $_[0]->{remoteid} ) };
    $vars->{mysql_time} = sub { $_[0] ? LJ::mysql_time( $_[0] ) : "" };

    return DW::Template->render_template( 'admin/userlog.tt', $vars );
}

1;
