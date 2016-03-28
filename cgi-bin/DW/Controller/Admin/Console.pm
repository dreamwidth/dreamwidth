#!/usr/bin/perl
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Admin::Console;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;
use LJ::Console;

=head1 NAME

DW::Controller::Admin::Console - Admin console

=cut

DW::Routing->register_string( "/admin/console/index", \&console_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'console/index',
    ml_scope => '/admin/console/index.tt',
);

DW::Routing->register_string( "/admin/console/reference", \&reference_handler, app => 1 );

sub reference_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $vars = {
        console_url => LJ::create_url( "/admin/console" ),

        command_list_html => LJ::Console->command_list_html,
        command_reference_html => LJ::Console->command_reference_html,
    };
    return DW::Template->render_template( 'admin/console/reference.tt', $vars );
}

sub console_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    my $commands_output;
    if ( $r->did_post ) {
        my $post = $r->post_args;
        my $commands = $post->{commands};
        $commands_output = LJ::Console->run_commands_html( $commands )
    }


    my $vars = {
        reference_url   => LJ::create_url( "/admin/console/reference" ),
        form_url        => LJ::create_url( undef ),

        show_extended_description => ! $r->did_post,
        commands => $commands_output,
    };
    return DW::Template->render_template( "admin/console/index.tt", $vars );
}

1;
