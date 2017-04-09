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


# viewing the queue and details for a specific import
DW::Routing->register_string( "/admin/importer/queue/index", \&queue_controller );
DW::Routing->register_string( "/admin/importer/details/index", \&detail_controller );

DW::Controller::Admin->register_admin_page( '/',
    path => 'importer/queue',
    ml_scope => '/admin/importer.tt',
    privs => [ 'siteadmin:theschwartz' ]
);


# view overall import history
DW::Routing->register_string( "/admin/importer/history/index", \&history_controller );

DW::Controller::Admin->register_admin_page( '/', ,
    path => 'importer/history',
    ml_scope => '/admin/importer/history.tt',
    privs => [ 'siteadmin:importhistory' ]
);

sub queue_controller {
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

    my $items = DW::Logic::Importer->get_queued_imports( $u );
    my $data = DW::Logic::Importer->get_import_data( $u, keys %$items );

    # 1. iterate over every import to get the user/host info
    # 2. iterate over every job in that import to add the user/host info
    foreach my $row ( @$data ) {
        my ( $importid, $host, $user, $usejournal ) = @$row;
        my $source = sprintf( "%s@%s", $usejournal || $user, $host );

        foreach my $key ( keys %{ $items->{$importid} } ) {
            $items->{$importid}->{$key}->{source} = $source;
        }
    }

    my $vars = { username => $u->ljuser_display, import_items => $items };

    if ( scalar keys %{$items||{}} > 1 ) {
        $vars->{errmsg} = ".error.toomanypending";
    }

    return DW::Template->render_template( 'admin/importer/detail.tt', $vars );
}

sub history_controller {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:importhistory" ] );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $get = $r->get_args;
    my $user = $get->{user};

    my $vars = {};

    if ( defined $user ) {
        my $u = LJ::load_user( $user );
        return error_ml( "error.invaliduser" ) unless $u;

        my $items = DW::Logic::Importer->get_all_import_items( $u );
        my $data = DW::Logic::Importer->get_import_data( $u, keys %$items );

        # 1. iterate over every import to get the user/host info
        # 2. iterate over every job in that import to add the user/host info
        foreach my $row ( @$data ) {
            my ( $importid, $host, $user, $usejournal ) = @$row;
            my $source = sprintf( "%s@%s", $usejournal || $user, $host );

            foreach my $key ( keys %{ $items->{$importid} } ) {
                $items->{$importid}->{$key}->{source} = $source;
            }
        }

        $vars->{username} = $u->ljuser_display;
        $vars->{import_items} = $items;
        $vars->{formdata} = $r->get_args;
    }

    return DW::Template->render_template( 'admin/importer/history.tt', $vars );
}

1;
