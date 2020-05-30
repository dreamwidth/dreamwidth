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

DW::Routing->register_string( "/admin/userlog", \&userlog_controller, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'userlog',
    ml_scope => '/admin/userlog.tt',
    privs    => [ 'canview:userlog', 'canview:*' ]
);

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
            map { $_ => 1 } qw(ban_set ban_unset maintainer_add maintainer_remove impersonator);

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
