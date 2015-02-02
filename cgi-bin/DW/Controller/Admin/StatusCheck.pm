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
use IO::Socket::INET ();

=head1 NAME

DW::Controller::Admin::StatusCheck - Checks the status of various services

=cut

DW::Routing->register_string( "/admin/healthy", \&healthy_handler, format => 'plain' );
DW::Controller::Admin->register_admin_page( '/',
    path => 'healthy',
    ml_scope => '/admin/healthy.tt',
);

DW::Routing->register_string( "/admin/theschwartz", \&theschwartz_handler );
DW::Controller::Admin->register_admin_page( '/',
    path => 'theschwartz',
    ml_scope => '/admin/theschwartz.tt',
    privs => [ 'siteadmin:theschwartz' ]
);

# Returns some healthy-or-not statistics on the site.  Intended to be used by
# remote monitoring services and the like.  This is supposed to be very
# lightweight, not designed to replace Nagios monitoring in any way.
# Printing as plain text to avoid having to parse HTML cruft
sub healthy_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    my ( @pass, @fail );

    # check 1) verify databases reachable
    my $dbh = LJ::get_db_writer();
    if ( $dbh ) {
        my $time = $dbh->selectrow_array( 'SELECT UNIX_TIMESTAMP()' );
        if ( ! $time || $dbh->err ) {
            push @fail, "global writer test query failed";
        } else {
            push @pass, "global writer";
        }
    } else {
        push @fail, "global writer unreachable";
    }

    # step 2) check all clusters
    foreach my $cid ( @LJ::CLUSTERS ) {
        my $dbcm = LJ::get_cluster_master( $cid );
        if ( $dbcm ) {
            my $time = $dbcm->selectrow_array( 'SELECT UNIX_TIMESTAMP()' );
            if ( ! $time || $dbcm->err ) {
                push @fail, "cluster $cid writer test query failed";
            } else {
                push @pass, "cluster $cid writer";
            }
        } else {
            push @fail, "cluster $cid writer unreachable";
        }
    }

    # verify connectivity to all memcache machines
    foreach my $memc ( @LJ::MEMCACHE_SERVERS ) {
        my $sock = IO::Socket::INET->new( PeerAddr => $memc, Timeout => 1 );

        if ( $sock ) {
            push @pass, "memcache $memc";
        } else {
            push @fail, "memcache $memc";
        }
    }

    # check each mogilefs server
    foreach my $mog ( @{ $LJ::MOGILEFS_CONFIG{hosts} || [] } ) {
        my $sock = IO::Socket::INET->new( PeerAddr => $mog, Timeout => 1 );

        if ( $sock ) {
            push @pass, "mogilefsd $mog";
        } else {
            push @fail, "mogilefsd $mog";
        }
    }

    # check each gearman server
    foreach my $gm ( @LJ::GEARMAN_SERVERS ) {
        my $sock = IO::Socket::INET->new( PeerAddr => $gm, Timeout => 1 );

        if ( $sock ) {
            push @pass, "gearman $gm";
        } else {
            push @fail, "gearman $gm";
        }
    }

    # and each Perlbal
    foreach my $pb ( values %LJ::PERLBAL_SERVERS ) {
        my $sock = IO::Socket::INET->new( PeerAddr => $pb, Timeout => 1 );

        if ( $sock ) {
            push @pass, "perlbal $pb";
        } else {
            push @fail, "perlbal $pb";
        }
    }

    if ( ! LJ::theschwartz() ) {
        # no schwartz
    } elsif ( scalar( grep { defined $_->{role} } @LJ::THESCHWARTZ_DBS ) > 0 || scalar( @LJ::THESCHWARTZ_DBS ) > 1 ) {
        # cannot test, leaving off
    } else {
        my $sid = 0;
        foreach my $db ( @LJ::THESCHWARTZ_DBS ) {
            my $s_db = DBI->connect( $db->{dsn}, $db->{user}, $db->{pass} );
            if ( $s_db ) {
                my $time = $s_db->selectrow_array( "DESCRIBE " . ( $db->{prefix} ? $db->{prefix}."_job" : "job" ) );
                if ( ! $time || $s_db->err ) {
                    push @fail, "schwartz $sid";
                } else {
                    push @pass, "schwartz $sid";
                }
            } else {
                push @fail, "schwartz $sid unreachable";
            }
            $sid++;
        }
    }

    my $out = '';
    if ( @fail ) {
        $out = "status=fail\n\nfailures:\n";
        $out .= join( "\n", map { "  $_" } @fail ) . "\n";
    } else {
        $out = "status=ok\n";
    }

    if ( @pass ) {
        $out .= "\nokay:\n";
        $out .= join( "\n", map { "  $_" } @pass ) . "\n";
    }

    $r->print( $out );
    return $r->OK;
}

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