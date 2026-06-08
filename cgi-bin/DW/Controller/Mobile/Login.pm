#!/usr/bin/perl
#
# DW::Controller::Mobile::Login
#
# Handles the mobile login page (/mobile/login), a minimal standalone
# (no sitescheme) login form for the lightweight mobile interface.
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

package DW::Controller::Mobile::Login;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

DW::Routing->register_string( "/mobile/login", \&login_handler, app => 1 );

sub login_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    # a plain GET while logged in means the "log out" link on /mobile/ was
    # followed -- log the user out and fall through to render the form
    if ( $remote && !$r->did_post ) {
        $remote->logout;
        $rv->{remote} = $remote = undef;
    }

    my $errors = DW::FormErrors->new;

    if ( $r->did_post ) {
        my $post = $r->post_args;

        my $u = LJ::load_user( $post->{user} );
        $errors->add( 'user', '.login.invalid_username' ) unless $u;

        if ($u) {
            my $banned;
            my $auth_ok = LJ::auth_okay( $u, $post->{password}, is_ip_banned => \$banned );

            if ($banned) {
                $errors->add( '', '.login.ip_banned' );
            }
            elsif ( !$auth_ok ) {
                $errors->add( 'password', '.login.badpass' );
            }
            else {
                $u->make_login_session('long');
                return $r->redirect( "$LJ::SITEROOT/mobile/?t=" . time() );
            }
        }
    }

    $rv->{errors} = $errors;

    return DW::Template->render_template( 'mobile/login.tt', $rv, { no_sitescheme => 1 } );
}

1;
