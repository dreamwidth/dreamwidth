#!/usr/bin/perl
#
# DW::Controller::Manage::EmailPost
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
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#

package DW::Controller::Manage::EmailPost;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

use DW::API::Key;
use LJ::Emailpost::Web;

DW::Routing->register_string( "/manage/emailpost", \&emailpost_handler, app => 1 );

sub emailpost_handler {
    my $ml_scope = "/manage/emailpost.tt";
    return error_ml("$ml_scope.error.sitenotconfigured") unless $LJ::EMAIL_POST_DOMAIN;

    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $u = $rv->{u};
    return DW::Template->render_template( 'error.tt', { message => $LJ::MSG_READONLY_USER } )
        if $u->is_readonly;

    return error_ml("$ml_scope.error.acct") unless $u->can_emailpost;

    $u->preload_props(
        qw/
            emailpost_pin emailpost_allowfrom
            emailpost_userpic emailpost_security
            emailpost_comments emailpost_gallery
            /
    );
    $rv->{u} = $u;

    my $r         = $rv->{r};
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;

    my ( $mode, $type ) = ( $form_args->{mode}, $form_args->{type} );

    if ( $mode && $mode eq 'help' ) {
        $rv->{type}      = $type;
        $rv->{format_to} = sub { sprintf "%s@%s", $_[0], $LJ::EMAIL_POST_DOMAIN };

        if ( my @addr = split /\s*,\s*/, $u->{emailpost_allowfrom} ) {
            my $email = $addr[0];
            $email =~ s/\(\w\)$//;
            $rv->{example} = $email;
        }

        return DW::Template->render_template( 'manage/emailpost_help.tt', $rv );
    }

    if ( $r->did_post && $form_args->{save} ) {

        # COME BACK TO THIS LATER
    }

    $rv->{addrlist} = LJ::Emailpost::Web::get_allowed_senders($u);
    $rv->{apikeys}  = DW::API::Key->get_keys_for_user($u);

    return DW::Template->render_template( 'manage/emailpost.tt', $rv );
}

1;
