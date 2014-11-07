#!/usr/bin/perl
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Admin::StatusCheck;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

=head1 NAME

DW::Controller::Admin::StatusCheck - Checks the status of various services

=cut

DW::Routing->register_string( "/admin/theschwartz", \&theschwartz_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'theschwartz',
    ml_scope => '/admin/theschwartz.tt',
    privs => [ 'siteadmin:theschwartz' ]
);

sub theschwartz_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:theschwartz' ] );
    return $rv unless $ok;

    # of course, if TheSchwartz is off...
    my $sch = LJ::theschwartz();
    return error_ml( "/admin/theschwartz.tt.error.noschwartz" ) unless $sch;

    # okay, this is really hacky, and I apologize in advance for inflicting this
    # on the codebase.  but we have no way of really getting into the database used
    # by TheSchwartz without this manual hackery... also, this requires that we not
    # be using roled TheSchwartz, or multiple (undefined results)
    #
    # FIXME: this can be so much better.
    return error_ml( "/admin/theschwartz.tt.error.config" )
        if scalar( grep { defined $_->{role} } @LJ::THESCHWARTZ_DBS ) > 0 ||
           scalar( @LJ::THESCHWARTZ_DBS ) > 1;

    # do manual connection
    my $db = $LJ::THESCHWARTZ_DBS[0];
    my $dbr = DBI->connect( $db->{dsn}, $db->{user}, $db->{pass} );
    return error_ml( "/admin/theschwartz.tt.error.manual" ) unless $dbr;

    # gather status on jobs in the queue
    my $job = ( $db->{prefix} || "" ) . "job";
    my $funcmap = ( $db->{prefix} || "" ) . "funcmap";
    my $jobs = $dbr->selectall_arrayref(
        qq{SELECT j.jobid, f.funcname,
                 FROM_UNIXTIME(j.insert_time), j.insert_time,
                 FROM_UNIXTIME(j.run_after), j.run_after,
                 FROM_UNIXTIME(j.grabbed_until), j.grabbed_until,
                 j.priority
          FROM $job j, $funcmap f
          WHERE f.funcid = j.funcid
          ORDER BY j.insert_time}
    );
    return error_ml( '/admin/theschwartz.tt.error.jobs', { error => $dbr->errstr } )
        if $dbr->err;

    # now get the actual data
    my @queue;
    if ( $jobs && @$jobs ) {
        foreach my $job ( @$jobs ) {
            my ( $jid, $fn, $it, $r_it, $ra, $r_ra, $gu, $r_gu, $pr ) = @$job;

            my $ago_it = LJ::diff_ago_text( $r_it );
            my $ago_ra = LJ::diff_ago_text( $r_ra );

            my $state;
            if ( !$r_ra && !$r_gu ) {
                $state = 'queued';
            } elsif ( $r_gu ) {
                if ( $r_ra ) {
                    $state = 'retrying';
                } else {
                    $state = 'running';
                }
            } elsif ( $r_ra && !$r_gu ) {
                if ( $r_ra < time ) {
                    $state = 'failed at least once, will retry very soon';
                } else {
                    $state = 'failed at least once, will retry in ' . $ago_ra;
                    $state =~ s/\s?ago\s?//; # heh
                }
            } else {
                $state = 'UNKNOWN';
            }

            $pr ||= 'undefined';
            push @queue, {
                jid => $jid,
                it  => $it,
                ago_it => $ago_it,
                fn => $fn,
                state => $state,
                priority => $pr
            };
        }
    }

    # gather some status on the last 100 errors.
    my $error = ( $db->{prefix} || "" ) . "error";
    my $errs = $dbr->selectall_arrayref(
        qq{SELECT e.jobid, FROM_UNIXTIME(e.error_time), f.funcname, e.message
          FROM $error e, $funcmap f
          WHERE f.funcid = e.funcid
          ORDER BY e.error_time DESC
          LIMIT 100}
    );
    return error_ml( '/admin/theschwartz.tt.error.recent', { error => $dbr->errstr } )
        if $dbr->err;

    return DW::Template->render_template( "admin/theschwartz.tt", {
        queue => \@queue,
        recent_errors => $errs,
    } );
}

1;