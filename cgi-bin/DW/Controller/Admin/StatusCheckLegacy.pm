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

DW::Routing->register_string( "/admin/mysql_status", \&mysql_status_handler, formats => [ 'html', 'plain' ] );
DW::Controller::Admin->register_admin_page( '/',
    path => 'mysql_status',
    ml_scope => '/admin/mysql_status.tt',
    privs => [ 'siteadmin:mysqlstatus', 'siteadmin:*' ]
);

sub mysql_status_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:mysqlstatus', 'siteadmin:*' ] );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $get = $r->get_args;

    my $mode = $get->{mode} || "status";
    my @modes = map {
        {   text    => ".mode.$_",
            url     => LJ::create_url( undef, args => { mode => $_ } ),
            active  => $_ eq $mode,
        }
    } qw(status variables tables);

    my $dbh = LJ::get_db_writer();
    my ( @data, @headers );

    if ( $mode eq "status" ) {
        my $sth;
        $sth = $dbh->prepare( "SHOW STATUS" );
        $sth->execute;
        my %s;
        while ( my ( $k, $v ) = $sth->fetchrow_array ) {
            $s{$k} = $v;
        }

        $sth = $dbh->prepare( "SHOW STATUS" );
        $sth->execute;
        while (my ( $k, $v ) = $sth->fetchrow_array) {
            my $delta = $v - $s{$k};
            if ($delta == 0) {
                $delta = "";
            } elsif ($delta > 0) {
                $delta = "+$delta";
            } else {
                $delta = "-$delta";
            }
            push @data, [ $k, $v, $delta ];
        }
    } elsif ( $mode eq "variables" ) {
        my $sth;
        $sth = $dbh->prepare( "SHOW VARIABLES" );
        $sth->execute;

        while ( my ( $k, $v ) = $sth->fetchrow_array ) {
            push @data, [ $k, $v ];
        }
    } elsif ( $mode eq "tables" ) {
        my $sth;
        $sth = $dbh->prepare( "SHOW TABLE STATUS" );
        $sth->execute;

        @headers = @{$sth->{NAME}};

        while ( my $t = $sth->fetchrow_hashref ) {
            my @row;
            push @row, $t->{$_} foreach @headers;
            push @data, \@row;
        }
    }

    if ( $opts->{format} eq 'plain' ) {
        $r->print( join(",", @headers ) . "\n" );
        $r->print( join( ",", @$_ ) . "\n" ) foreach @data;
        return $r->OK;
    }

    my $vars = {
        mode_links  => \@modes,
        mode        => $mode,

        text_version_link => LJ::create_url( $r->uri . ".plain", keep_args => 1 ),

        data    => \@data,
        headers => \@headers,
    };

    return DW::Template->render_template( "admin/mysql_status.tt", $vars );
}

sub clusterstatus_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( privcheck => [ "supporthelp" ], );
    return $rv unless $ok;

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