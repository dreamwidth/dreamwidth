#!/usr/bin/perl
#
# DW::Controller::Manage::Notifications
#
# Account notification settings.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Manage::Notifications;

use strict;
use warnings;

use DW::Controller;
use DW::Controller::SettingsHub ();
use DW::Routing;
use DW::Template;
use LJ::Web;

my $path  = '/manage/settings/notifications';
my $scope = '/tracking/settings-interface.tt';

DW::Routing->register_string(
    $path, \&notification_settings,
    app     => 1,
    methods => { GET => 1, HEAD => 1, POST => 1 },
);

sub notification_settings {
    my ( $ok, $vars ) = controller( authas => 1, form_auth => 1 );
    return $vars unless $ok;

    my ( $r, $remote, $u ) = @{$vars}{qw(r remote u)};
    my $get            = $r->get_args;
    my $can_view_other = $remote->has_priv( 'canview', 'subscriptions' );

    if ( $can_view_other && $get->{user} ) {
        $u = LJ::load_user( $get->{user} ) || $u;
    }

    if ( $u->is_community ) {
        return error_ml('error.invalidauth') if $r->did_post || !$vars->{u}->equals($u);
        return $r->redirect(
            LJ::create_url( '/manage/settings/', args => { authas => $u->user, cat => 'account' } )
        );
    }

    my $viewing_self = $remote->equals($u) && $remote->equals( $vars->{u} );
    if ( $r->did_post ) {
        return error_ml('error.invalidauth') unless $viewing_self;
        my $post = $vars->{post_args};

        if ( $post->{deleteinactive} ) {
            $u->delete_all_inactive_subscriptions;
            $vars->{notice} = LJ::Lang::ml('/settings/index.tt.success.deleteinactive2');
        }
        elsif ( my $delete_id = $post->{delete_subscription} ) {
            my $subscription = DW::Controller::SettingsHub::_owned_subscription( $u, $delete_id );
            return error_ml('error.invalidform') unless $subscription;
            $subscription->delete;
            $vars->{notice} = LJ::Lang::ml("$scope.success.deleted");
        }
        else {
            my @errors = $u->save_subscriptions($post);
            delete $u->{_subscriptions};
            if (@errors) {
                $vars->{subscription_errors} = [ map { $_->as_html } @errors ];
            }
            else {
                my $return_url =
                    DW::Controller::SettingsHub::_notification_return_url( $r, $post->{ret_url} );
                if ($return_url) {
                    return DW::Controller::SettingsHub::_settings_redirect( $r, $return_url, 302 )
                        if $post->{post_to_settings_page};
                    return $r->redirect($return_url);
                }
                $vars->{notice} = LJ::Lang::ml('/settings/index.tt.success');
            }
        }
    }

    $u->subscription_default_setup if $viewing_self;
    my $page = $get->{page} || 1;
    $page = 1 unless $page =~ /\A[1-9][0-9]{0,8}\z/;

    my $subscriptions = LJ::subscription_interface_data(
        $u,
        journal       => $u,
        categories    => $u->subscription_categories_for_settings_page,
        settings_page => 1,
        page          => $page,
    );

    return DW::Template->render_template(
        'tracking/settings-interface.tt',
        {
            %$subscriptions,
            %$vars,
            account_name   => $u->display_username,
            can_view_other => $can_view_other,
            lookup_user    => $get->{user},
            authas         => $get->{authas},
            post_action    => LJ::create_url( $path, keep_args => ['page'] ),
            viewing_self   => $viewing_self,
            confirm_msg    => DW::Controller::SettingsHub::_settings_confirm_message(),
        }
    );
}

1;
