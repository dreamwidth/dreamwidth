#!/usr/bin/perl
#
# DW::Controller::Admin::SpamReports
#
# Manage reports of unsolicited messages and comments.
# Requires siteadmin:spamreports or siteadmin:* privileges.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::SpamReports;

use strict;

use DW::Controller;
use DW::Controller::Admin;
use DW::Routing;
use DW::Template;

use LJ::Sysban;

DW::Routing->register_string( "/admin/spamreports", \&main_controller, app => 1 );
DW::Controller::Admin->register_admin_page( '/',
    path => 'spamreports',
    ml_scope => '/admin/spamreports/index.tt',
    privs => [ 'siteadmin:spamreports', 'siteadmin:*' ]
);

sub main_controller {
    my ( $ok, $rv ) = controller( form_auth => 1,
                      privcheck => [ 'siteadmin:spamreports', 'siteadmin:*' ] );
    return $rv unless $ok;
    my $remote = $rv->{remote};

    my $r = DW::Request->get;
    my $scope = '/admin/spamreports/index.tt';

    # determine view mode; 'get' takes priority over 'post'
    my $mode = lc( $r->get_args->{mode} || $r->post_args->{mode} || '' );
    $mode = '' if $mode =~ /^del/ && ! $r->did_post && ! LJ::check_referer('/admin/spamreports');

    # check mode suffix for users only (u), anon only(a), or combined (c)
    my $view = $mode =~ /_([cua])$/ ? $1 : 'c';  # default is combined view
    $mode =~ s/_[cua]$//; # strip out viewing option

    my %extrawhere = ( c => '1', u => 'posterid > 0', a => 'posterid = 0' );

    $rv->{mode} = $mode;
    $rv->{view} = $view;

    # helper function for constructing links to view reports
    my $viewlink = sub {
        my ( $by, $what, $state, $reporttime, $etext ) = @_;
        $reporttime = LJ::mysql_time( $reporttime ) if defined $reporttime;
        my $linktext = $etext // $reporttime // '[error: no text]';
        ( $by, $what, $state ) = map { LJ::eurl($_) } ( $by, $what, $state );
        return "<a href=\"spamreports?mode=view&amp;by=$by&amp;what=$what&amp;state=$state\">$linktext</a>";
    };

    # helper function for constructing buttons to close reports
    my $closeform = sub {
        my ( $srids, $text ) = @_;
        return
            LJ::html_hidden( mode => 'del' ) .
            LJ::html_hidden( srids => join( ',', @$srids ) ) .
            LJ::html_hidden( ret => LJ::create_url( undef, keep_args => 1 ) ) .
            LJ::html_submit( submit => $text );
    };

    # retrieve and display the requested rows from the database
    my $dbr = LJ::get_db_reader();
    return error_ml( "$scope.error.db.noread" ) unless $dbr;
    my @rows;

    if ( $mode eq 'top10ip' ) { # top 10 by ip
        my $res = $dbr->selectall_arrayref(
            "SELECT COUNT(ip) AS num, ip, MAX(reporttime) FROM spamreports" .
            " WHERE state = 'open' AND ip IS NOT NULL" .
            " GROUP BY ip ORDER BY num DESC LIMIT 10" );
        foreach ( @$res ) {
            push @rows, [ $_->[0], $_->[1],
                          $viewlink->( 'ip', $_->[1], 'open', $_->[2] )
                        ];
        }

        $rv->{rows} = \@rows;
        $rv->{count} = scalar @rows;
        $rv->{headers} = [ qw( .header.numreports .header.ipaddress
                               .header.mostrecentreport ) ];

        return DW::Template->render_template( 'admin/spamreports/toptable.tt', $rv );

    } elsif ( $mode eq 'top10user' ) { # top 10 by user
        my $res = $dbr->selectall_arrayref(
            "SELECT COUNT(posterid) AS num, posterid, MAX(reporttime) FROM spamreports" .
            " WHERE state = 'open' AND posterid > 0" .
            " GROUP BY posterid ORDER BY num DESC LIMIT 10" );
        foreach ( @$res ) {
            my $u = LJ::load_userid( $_->[1] );
            push @rows, [ $_->[0], LJ::ljuser($u),
                          $viewlink->( 'posterid', $_->[1], 'open', $_->[2] )
                        ];
        }

        $rv->{rows} = \@rows;
        $rv->{count} = scalar @rows;
        $rv->{headers} = [ qw( .header.numreports .header.postedbyuser
                               .header.mostrecentreport ) ];

        return DW::Template->render_template( 'admin/spamreports/toptable.tt', $rv );

    } elsif ( $mode eq 'tlast10' ) { # most recent 10 reports
        my $res = $dbr->selectall_arrayref(
            "SELECT posterid, ip, journalid, reporttime FROM spamreports" .
            " WHERE state = 'open' AND $extrawhere{$view}" .
            " ORDER BY reporttime DESC LIMIT 10" );
        foreach ( @$res ) {
            my $ju = LJ::load_userid( $_->[2] );
            if ( $_->[0] > 0 ) {  # user report
                my $u = LJ::load_userid( $_->[0] );
                push @rows, [ LJ::ljuser($u), LJ::ljuser($ju),
                              $viewlink->( 'posterid', $_->[0], 'open', $_->[3] )
                            ];
            } else {  # anonymous report
                push @rows, [ $_->[1], LJ::ljuser($ju),
                              $viewlink->( 'ip', $_->[1], 'open', $_->[3] )
                            ];
            }
        }

        $rv->{rows} = \@rows;
        $rv->{count} = scalar @rows;
        $rv->{headers} = [ qw( .header.postedby .header.postedin
                               .header.reporttime ) ];

        return DW::Template->render_template( 'admin/spamreports/toptable.tt', $rv );

    } elsif ( $mode =~ /^last(\d+)hr$/ ) { # reports in last X hours
        my $hours = $1 + 0;
        my $secs = $hours * 3600;  # seconds in an hour
        $rv->{hours} = $hours;
        $rv->{mode} = 'tlasthrs';  # now that we know the number of hours

        my $res = $dbr->selectall_arrayref(
            "SELECT ip, posterid, reporttime FROM spamreports" .
            " WHERE $extrawhere{$view} AND reporttime > (UNIX_TIMESTAMP() - $secs)" .
            " LIMIT 1000" );

        # count up items and their most recent report
        my %hits;
        my %times;
        foreach ( @$res ) {
            my ( $ip, $posterid, $reporttime ) = @$_;
            my $key;

            if ( $posterid > 0 ) {
                my $u = LJ::load_userid( $posterid );
                $key = $u->userid if $u;
            } else {
                $key = $ip if $ip;
            }

            if ( defined $key ) {
                $hits{$key}++;
                $times{$key} = $reporttime
                    unless defined $times{$key} && $times{$key} gt $reporttime;
            }
        }

        # now reverse %hits to number => item(s) list
        my %revhits;
        foreach ( keys %hits ) {
            my $num = $hits{$_};
            $revhits{$num} ||= [];
            push @{ $revhits{$num} }, $_;
        }

        # now push them onto @rows
        foreach ( sort { $b <=> $a } keys %revhits ) {
            my $r = $revhits{$_};
            foreach ( @$r ) {
                if ( /^\d+$/ ) {  # userid
                    my $u = LJ::load_userid( $_ );
                    push @rows, [ $hits{$_}, LJ::ljuser($u),
                                  $viewlink->( 'posterid', $_, 'open', $times{$_} )
                                ];
                } else {  # assumed to be IP address
                    push @rows, [ $hits{$_}, $_,
                                  $viewlink->( 'ip', $_, 'open', $times{$_} )
                                ];
                }
            }
        }

        $rv->{rows} = \@rows;
        $rv->{count} = scalar @rows;
        $rv->{headers} = [ qw( .tlasthrs.numreports .tlasthrs.postedby
                               .tlasthrs.reporttime ) ];

        return DW::Template->render_template( 'admin/spamreports/toptable.tt', $rv );

    } elsif ( $mode eq 'view' ) { # view a particular report
        my $get = $r->get_args;
        my ( $by, $what, $state ) =
            ( lc( $get->{by} || '' ), $get->{what}, lc( $get->{state} || '' ) );
        $by = '' unless $by =~ /^(?:ip|poster(?:id)?)$/;
        $state = 'open' unless $state =~ /^(?:open|closed)$/;

        # check to see whether the viewer requested a posttime sort instead
        my $sort = lc( $get->{sort} || '' );
        $sort = 'reporttime' unless $sort =~ /^(?:reporttime|posttime)$/;

        $rv->{view_by}    = $by;
        $rv->{view_what}  = $what;
        $rv->{view_state} = $state;
        $rv->{view_sort}  = $sort;

        my %flip = ( reporttime => 'posttime', posttime => 'reporttime' );

        $rv->{sorturl} = LJ::create_url( undef, keep_args => 1,
                                         args => { sort => $flip{$sort} } );

        if ( $state eq 'open' ) {
            $rv->{statelink} = $viewlink->( $by, $what, 'closed', undef,
                               LJ::Lang::ml( "$scope.view.closedreports" ) );
        } else {
            $rv->{statelink} = $viewlink->( $by, $what, 'open', undef,
                               LJ::Lang::ml( "$scope.view.openreports" ) );
        }

        if ( $by eq 'posterid' ) {
            $what += 0 if defined $what;
            my $u = LJ::load_userid( $what );
            return error_ml( "$scope.error.noposterid" ) unless $u;

            $rv->{view_u} = $u;
            $rv->{show_posted} = LJ::is_enabled( 'show-talkleft' )
                                 && $u->is_individual;

        } elsif ( $by eq 'poster' ) {
            my $u = LJ::load_user( $what );
            return error_ml( "$scope.error.nouser" ) unless $u;

            # Now just pretend that user used 'posterid'
            $by = 'posterid';
            $what = $u->userid;
            $rv->{view_u} = $u;

        } elsif ( $by eq 'ip' ) {
            # don't worry about IP format, just do a length check
            # if the IP is in the results table, we consider it valid
            # if it's not, we'll get a noreports error later, so it's all good
            return error_ml( "$scope.error.noip" ) if length $what > 45;

            $rv->{reason} = LJ::Sysban::populate_full_by_value( $what, 'talk_ip_test' );
            $rv->{is_ipv4} = ( $what =~ /^\d+\.\d+\.\d+\.\d+$/ ) ? 1 : 0;
            $rv->{timestr} = LJ::mysql_time();
        }

        # now the general info gathering
        my $res = $by ? $dbr->selectall_arrayref(
            "SELECT reporttime, journalid, subject, body, posttime, report_type," .
            " srid, client FROM spamreports WHERE state=? AND $by=?" .
            " ORDER BY ? DESC LIMIT 1000", undef, $state, $what, $sort ) : [];
        my @srids;
        foreach ( @$res ) {
            my $reporttime = LJ::mysql_time( $_->[0] );
            my $ju = LJ::load_userid( $_->[1] );
            my $comment_subject = $_->[2];
            my $comment_body = $_->[3];
            LJ::text_uncompress( \$comment_body );
            my $posttime = $_->[4] ? LJ::mysql_time( $_->[4] ) : undef;
            my $spamlocation = ucfirst $_->[5];
            my $srid = $_->[6];
            my $client = $_->[7] || '';

            push @srids, $srid;
            push @rows, { srid => $srid, spamloc => $spamlocation,
                          journal => $ju, reporttime => $reporttime,
                          posttime => $posttime, client => $client,
                          subject => $comment_subject,
                          body => $comment_body };
        }

        $rv->{srids} = \@srids;
        $rv->{rows} = \@rows;
        $rv->{count} = scalar @rows;

        $rv->{commafy} = sub { LJ::commafy( $_[0] ) };
        $rv->{closeform} = sub { $closeform->( @_ ) };

        return DW::Template->render_template( 'admin/spamreports/view.tt', $rv );
    }

    # if deletion was requested, do post processing
    if ( $mode eq 'del' ) {
        my $dbh =  LJ::get_db_writer();
        return error_ml( "$scope.error.db.nowrite" ) unless $dbh;
        my $post = $r->post_args;

        # split srid argument at commas and reconstruct using quotes
        my @srids = split( ',', $post->{srids} );
        my $in = join( "','", map { $_ + 0 } @srids );
        $in = "'$in'";

        if ( $post->{sysban_ip} && $remote->has_priv( 'sysban', "talk_ip_test" )
               && ! LJ::Sysban::validate( "talk_ip_test", $post->{sysban_ip} ) ) {
            LJ::Sysban::create(
                what => 'talk_ip_test', value => $post->{sysban_ip}, bandays => 0,
                note => $post->{sysban_note} || LJ::Lang::ml( "$scope.reports.individual.sysban.anon" ) );
        }

        my $count = $dbh->do( "UPDATE spamreports SET state='closed'" .
                              " WHERE srid IN ($in) AND state='open'" );

        return error_ml( "$scope.error.db.failure", { dberr => $dbh->errstr } )
            if $dbh->err;

        $rv->{count} = $count + 0;
        $rv->{ret} = $post->{ret};  # already escaped

        return DW::Template->render_template( 'admin/spamreports/closed.tt', $rv );

    } else {
        # no valid mode requested - show default page of links
        $rv->{modes} = { top10user => '.mode.top10user',
                         top10ip   => '.mode.top10ip',
                         tlast10   => '.mode.tlast10',
                         last01hr  => '.mode.tlasthrs.01',
                         last06hr  => '.mode.tlasthrs.06',
                         last24hr  => '.mode.tlasthrs.24',
                       };

        $rv->{useronly} = sub { "spamreports?mode=${_[0]}_u" };
        $rv->{anononly} = sub { "spamreports?mode=${_[0]}_a" };

        return DW::Template->render_template( 'admin/spamreports/index.tt', $rv );
    }
}

1;
