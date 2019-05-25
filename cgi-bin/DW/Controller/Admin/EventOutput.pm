#!/usr/bin/perl
#
# DW::Controller::Admin::EventOutput
#
# This controller is for getting a preview of the output for events, for easy debugging.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::EventOutput;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

use LJ::Event;
use LJ::Subscription;

DW::Routing->register_string( '/admin/eventoutput', \&event_output, app => 1 );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => '/admin/eventoutput',
    ml_scope => '/admin/eventoutput-select.tt',
    privs    => [
        sub {
            return ( $LJ::IS_DEV_SERVER, LJ::Lang::ml("/admin/index.tt.devserver") );
        }
    ]
);

sub event_output {
    my $r = DW::Request->get;

    # we have no security-checks past this point, so we never want to run this
    # on a site with actual user data.
    return $r->NOT_FOUND unless $LJ::IS_DEV_SERVER;

    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    if ( $r->method eq "POST" ) {
        return handle_post( %{ $r->post_args } );
    }
    else {
        my $get = $r->get_args;

        my @event_classes = map { $_ => $_ } sort LJ::Event->all_classes;
        my %event_map     = @event_classes;

        my $event = LJ::trim( $get->{event} );
        $event = undef unless $event_map{$event};

        my $vars = {
            eventtypes => \@event_classes,

            event     => $event,
            eventargs => $event ? [ $event->arg_list ] : undef,
        };
        return DW::Template->render_template( 'admin/eventoutput-select.tt', $vars );
    }
}

sub handle_post {
    my (%post) = @_;

    return error_ml("error.invalidform") unless LJ::check_form_auth( $post{lj_form_auth} );

    my $ju        = LJ::load_user( $post{eventuser} );
    my $eventtype = LJ::Event->event_to_etypeid( $post{event} );
    my $event     = LJ::Event->new_from_raw_params( $eventtype, $ju ? $ju->userid : 0,
        $post{arg1}, $post{arg2} );

    my $u = LJ::load_user( $post{subscr_user} );

    my $subscription_arg1 = int $post{sarg1};
    my $subscription_arg2 = int $post{sarg2};

    my $html_body = $event->as_email_html($u);
    $html_body = LJ::html_newlines($html_body) unless $html_body =~ m!<br!i;

    my $fake_subscr = LJ::Subscription->new_from_row(
        {
            userid  => $u->id,
            ntypeid => LJ::NotificationMethod::Email->ntypeid,
            etypeid => $eventtype,
            arg1    => $subscription_arg1,
            arg2    => $subscription_arg2,
        }
    );

    my $vars = {
        event => {
            email => {
                from      => $event->as_email_from_name($u) . " <$LJ::BOGUS_EMAIL>",
                to        => $u->email_raw,
                headers   => $event->as_email_headers($u),
                subject   => $event->as_email_subject($u),
                body_html => $html_body,
                body_text => $event->as_email_string($u),

                send => $event->matches_filter($fake_subscr),
            },

            inbox => {
                subject => $event->as_html($u),
                body    => $event->content($u),
                summary => $event->content_summary($u),
            }
        },
        su => $u,
    };

    return DW::Template->render_template( 'admin/eventoutput.tt', $vars );
}

1;
