#!/usr/bin/perl
#
# DW::Controller::Admin::Approve
#
# Interface for screening new accounts for spam content.
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

package DW::Controller::Admin::Approve;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

my $privs = [
    'siteadmin:approvenew',     # just for this page
    'siteadmin:spamreports',    # include existing antispam team
    'suspend',                  # include anyone with generic suspend privs
    'suspend:recent',           # just for this page
];

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'recent_accounts',
    ml_scope => '/admin/recent_accounts/review.tt',
    privs    => $privs
);

DW::Routing->register_string( '/admin/recent_accounts', \&approve_handler, app => 1 );

sub approve_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, privcheck => $privs );
    return $rv unless $ok;

    my $scope = '/admin/recent_accounts/review.tt';

    my $prop = LJ::get_prop( 'user', 'not_approved' );
    return error_ml( "$scope.error.disabled", { sitenameshort => $LJ::SITENAMESHORT } )
        unless $prop && LJ::is_enabled('approvenew');

    my $r         = $rv->{r};
    my $remote    = $rv->{remote};
    my $form_args = $r->post_args;
    my $vars      = {};

    $vars->{can_suspend} = 1
        if $remote->has_priv( 'suspend', '' ) || $remote->has_priv( 'suspend', 'recent' );

    return DW::Template->render_template( 'admin/recent_accounts/review.tt', $vars )
        unless $r->did_post;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare( "SELECT userid FROM userproplite2 "
            . "WHERE upropid=? AND value=? ORDER BY userid LIMIT ?" );

    my $get_users = sub {
        my ( $value, $limit ) = @_;
        $sth->execute( $prop->{id}, $value, $limit );
        die $dbr->errstr if $dbr->err;

        my @uids;
        push @uids, $_->[0] while $_ = $sth->fetchrow_arrayref;
        return LJ::load_userids(@uids);    # hashref
    };

    if ( $form_args->{begin} ) {

        # get a user to review - we don't want to just get the first result,
        # high chance of collision with multiple active reviewers
        my $users = $get_users->( 1, 5 );

        # make sure the accounts are at least an hour old - sorting
        # SELECT by userid means oldest accounts will be reviewed first
        my $now = time;
        foreach ( keys %$users ) {
            delete $users->{$_} if $users->{$_}->timecreate > $now - 3600;
        }

        my @ids = sort keys %$users;
        if ( my $num = scalar @ids ) {
            my $pickrand = int( rand($num) );
            $vars->{user} = $users->{ $ids[$pickrand] };
            $vars->{ago}  = LJ::diff_ago_text( $vars->{user}->timecreate );
            return DW::Template->render_template( 'admin/recent_accounts/user.tt',
                $vars, { no_sitescheme => 1 } );
        }
        else {
            return error_ml("$scope.error.nousers");
        }
    }

    if ( $form_args->{uid} ) {
        my $u       = LJ::load_userid( $form_args->{uid} );
        my $success = DW::FormErrors->new;
        my $value;

        # take action based on form_args - either clear or escalate
        $value = 0 if $form_args->{yes};
        $value = 2 if $form_args->{no};

        return error_ml('error.invalidform') unless defined $value;

        my $act = $value ? 'rejected' : 'approved';
        $success->add( '', ".success.$act", { user => $u->ljuser_display } );

        # reinforce the different colors for rejection vs approval
        $vars->{ $value ? 'errors' : 'success' } = $success;

        # force lookup in case someone else just changed this - we still show
        # the success message to the user, but don't perform the actions again
        delete $u->{"not_approved"};
        $u->preload_props( { use_master => 1 }, "not_approved" );

        if ( $u->prop('not_approved') && $u->prop('not_approved') == 1 ) {
            $u->set_prop( not_approved => $value );
            my $msg = sprintf( "new account %s $act by %s", $u->user, $remote->user );
            LJ::statushistory_add( $u, $remote, 'approvenew', $msg );

            # I thought about automatically doing the suspension here if
            # $remote had suspend privs, but I think it's better to give the
            # user a chance to review their actions in case of fat fingering
        }

        return DW::Template->render_template( 'admin/recent_accounts/review.tt', $vars );
    }

    if ( $form_args->{suspend} ) {
        return $r->redirect("$LJ::SITEROOT/admin/recent_accounts")
            unless $vars->{can_suspend};

        # get a list of flagged users to review for suspension
        $vars->{users} = $get_users->( 2, 10 );

        return DW::Template->render_template( 'admin/recent_accounts/suspend.tt', $vars );
    }

    if ( $form_args->{do_suspend} ) {
        my @ids = split / /, $form_args->{uids};
        return error_ml('error.invalidform') unless @ids && $vars->{can_suspend};

        my $users   = LJ::load_userids(@ids);
        my $success = DW::FormErrors->new;
        my $count   = 0;

        foreach my $uid (@ids) {
            my $u = $users->{$uid};
            next if $u->is_suspended;    # already done

            if ( $form_args->{"user_$uid"} ) {
                $u->set_suspended( $remote, "from /admin/recent_accounts" );
                $count++;
            }
            else {
                $u->set_prop( not_approved => 0 );
                LJ::statushistory_add( $u, $remote, 'approvenew',
                    sprintf( "new account %s approved by %s", $u->user, $remote->user ) );
            }
        }

        $success->add( '', '.success.suspend', { count => $count } );
        $vars->{success} = $success;

        return DW::Template->render_template( 'admin/recent_accounts/review.tt', $vars );
    }

    return error_ml('error.invalidform');    # no form args we know how to handle
}

1;
