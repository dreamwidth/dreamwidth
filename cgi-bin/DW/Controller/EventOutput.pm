#!/usr/bin/perl
#
# DW::Controller::EventPreview
#
# This controller is for getting a preview of the output for events, for easy debugging.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::EventOutput;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Event;

DW::Routing->register_string( '/admin/eventoutput', \&event_output, app => 1 );

sub event_output {
    my $r = DW::Request->get;

    # we have no security-checks past this point, so we never want to run this
    # on a site with actual user data.
    return $r->NOT_FOUND unless $LJ::IS_DEV_SERVER;

    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    if ( $r->method eq "POST" ) {
        return handle_post( %{ DW::Request->get->post_args || {} } );
    } else {
        my @event_classes = map { 
                { id    => LJ::Event->event_to_etypeid( $_ ),
                  name => $_ 
                }
            } sort LJ::Event->all_classes;
        my $vars = {
            eventtypes => \@event_classes,
        };
        return DW::Template->render_template( 'admin/eventoutput-select.tt', $vars );
    }
}

sub handle_post {
    my ( %post ) = @_;

    return error_ml( "error.invalidform" ) unless LJ::check_form_auth( $post{lj_form_auth} );

    my $ju = LJ::load_user( $post{eventuser} );
    my $event = LJ::Event->new_from_raw_params( $post{eventtype}, $ju ? $ju->userid : 0, $post{arg1}, $post{arg2} );

    my $u = LJ::load_user( $post{subscr_user} );

    my $html_body = $event->as_email_html( $u );
    $html_body = LJ::html_newlines( $html_body ) unless $html_body =~ m!<br!i;
    my $vars = {
        event => {
            email   => {
                from        => $event->as_email_from_name( $u ) . " <$LJ::BOGUS_EMAIL>",
                to          => $u->email_raw,
                headers     => $event->as_email_headers( $u ),
                subject     => $event->as_email_subject( $u ),
                body_html   => $html_body,
                body_text   => $event->as_email_string( $u ),
            },

            inbox   => {
                subject => $event->as_html( $u ),
                body    => $event->content( $u ),
                summary => $event->content_summary( $u ),
            }
        },
        su    => $u,
    };

    return DW::Template->render_template( 'admin/eventoutput.tt', $vars );
}

1;
