#!/usr/bin/perl
#
# DW::Controller::Importer
#
# Controller for the /tools/importer pages.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Importer;

use strict;
use warnings;

use DW::Routing;
use DW::Template;
use LJ::Hooks;

DW::Routing->register_string( '/tools/importer/erase', \&erase_handler, app => 1 );

sub erase_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    unless ( $r->did_post ) {

        # No post, return form.
        return DW::Template->render_template(
            'tools/importer/erase.tt',
            {
                authas_html => $rv->{authas_html},
                u           => $rv->{u},
            }
        );
    }

    my $args = $r->post_args;
    die "Invalid form auth.\n"
        unless LJ::check_form_auth( $args->{lj_form_auth} );

    unless ( $args->{confirm} eq 'DELETE' ) {
        return DW::Template->render_template(
            'tools/importer/erase.tt',
            {
                notconfirmed => 1,
                authas_html  => $rv->{authas_html},
                u            => $rv->{u},
            }
        );
    }

    # Confirmed, let's schedule.
    my $sclient = LJ::theschwartz() or die "Unable to get TheSchwartz.\n";
    my $job     = TheSchwartz::Job->new_from_array(
        'DW::Worker::ImportEraser',
        {
            userid => $rv->{u}->userid
        }
    );
    die "Failed to insert eraser job.\n"
        unless $job && $sclient->insert($job);

    return DW::Template->render_template(
        'tools/importer/erase.tt',
        {
            u         => $rv->{u},
            confirmed => 1,
        }
    );
}

1;
