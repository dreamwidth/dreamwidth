#!/usr/bin/perl
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.

package DW::Controller::Admin::StatusCheckLegacy;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

=head1 NAME

DW::Controller::Admin::StatusCheck - Pages where you can check the status of various services

=cut

DW::Routing->register_string( "/admin/clusterstatus", \&clusterstatus_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'clusterstatus',
    ml_scope => '/admin/clusterstatus.tt',
    privs => [ "supporthelp" ]
);

sub clusterstatus_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( privcheck => [ "supporthelp" ], );
    return $rv unless $ok;

    my $r = $rv->{r};

    my @clusters;
    foreach my $cid ( @LJ::CLUSTERS ) {
        my $cluster = { name => LJ::DB::get_cluster_description( $cid ) };

        if ( $LJ::READONLY_CLUSTER{$cid} ) {
            $cluster->{status} = "readonly";
        } elsif ( $LJ::READONLY_CLUSTER_ADVISORY{$cid} eq 'when_needed' ) {
            $cluster->{status} = "when_needed";
        } elsif ( $LJ::READONLY_CLUSTER_ADVISORY{$cid} ) {
            $cluster->{status} = "limited";
        } else {
            $cluster->{status} = "okay";

            my $dbcm = LJ::get_cluster_master( $cid );
            if ( $dbcm ) {
                $cluster->{available} = 1;
            } else {
                $cluster->{available} = 0;
            }
        }

        push @clusters, $cluster;
    }

    return DW::Template->render_template( "admin/clusterstatus.tt", {
        clusters => \@clusters,
    } );
}

1;