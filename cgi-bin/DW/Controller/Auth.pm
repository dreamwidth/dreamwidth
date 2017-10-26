#!/usr/bin/perl
#
# DW::Controller::Auth
#
# This controller is for authentication endpoints. Login, logout, and other
# related functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Rename;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger( __PACKAGE__ );

use DW::Controller;
use DW::FormErrors;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/logout", \&logout_handler, app => 1 );

sub logout_handler {
    # We have to allow anonymous viewers because that's how we render the page that
    # tells the user they have successfully logged out
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $remote = $rv->{remote};
    my $vars = {};

    if ( $r->did_post ) {
        my $post_args = $r->post_args;
        if ( exists $post_args->{logout_one} ) {
            $remote->logout;
            $vars->{success} = 'one';
        } elsif ( exists $post_args->{logout_all} ) {
            $remote->logout_all;
            $vars->{success} = 'all';
        }
    }

    # GET case or the logout success case
    return DW::Template->render_template( 'auth/logout.tt', $vars );
}

1;
