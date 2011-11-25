#!/usr/bin/perl
#
# DW::Controller::Importer
#
# This controller is to view details about the import queue
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Importer;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

use DW::Logic::Importer;

DW::Routing->register_string( "/admin/importer/index", \&index_controller );
DW::Routing->register_string( "/admin/importer/details/index", \&detail_controller );

DW::Controller::Admin->register_admin_page( '/',
    path => 'importer/',
    ml_scope => '/admin/importer.tt',
    privs => [ 'siteadmin:theschwartz' ]
);

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:theschwartz" ] );
    return $rv unless $ok;

    my $vars = {};
    my $sclient = LJ::theschwartz();
    my @joblist = $sclient->list_jobs( { funcname => [qw(   DW::Worker::ContentImporter::LiveJournal::Bio
                                DW::Worker::ContentImporter::LiveJournal::Tags
                                DW::Worker::ContentImporter::LiveJournal::Entries
                                DW::Worker::ContentImporter::LiveJournal::Comments
                                DW::Worker::ContentImporter::LiveJournal::Userpics
                                DW::Worker::ContentImporter::LiveJournal::Friends
                                DW::Worker::ContentImporter::LiveJournal::FriendGroups
                                DW::Worker::ContentImporter::LiveJournal::Verify
                            )] } );

    my @latest;
    my @jobs;
    foreach my $job ( @joblist ) {
        my $funcname = $job->funcname;
        my $arg = $job->arg;
        my $u = LJ::load_userid( $arg->{userid} );
        my $latest_id = DW::Logic::Importer->get_import_data_for_user( $u )->[0]->[0];

        push @latest, [ $u, $latest_id ];

        push @jobs, { type => $funcname,
                      user => $u->ljuser_display,
                      username => $u->username,
                      importid => { job => $arg->{import_data_id}, latest => $latest_id },
                    };
    }
    $vars->{jobs} = \@jobs;

    return DW::Template->render_template( 'admin/importer.tt', $vars );
}

sub detail_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:theschwartz" ] );
    return $rv unless $ok;

    my $get = DW::Request->get->get_args;
    my $user = $get->{user};

    my $u = LJ::load_user( $user );
    return error_ml( "error.invaliduser" ) unless $u;

    my $import_items = DW::Logic::Importer->get_queued_imports( $u );
    my $vars = { username => $u->ljuser_display, import_items => $import_items };

    if ( scalar keys %{$import_items||{}} > 1 ) {
        $vars->{errmsg} = ".error.toomanypending";
    }

    return DW::Template->render_template( 'admin/importer/detail.tt', $vars );
}

1;
