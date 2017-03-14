#!/usr/bin/perl
#
# DW::Controller::Support::History
#
# This controller is for the Support History page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::History;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/history', \&history_handler, app => 1 );

sub history_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;
    $args = $r->post_args if $r->did_post;

    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $vars = {};

    my $remote = $rv->{remote};
    my $fullsearch = $remote->has_priv( 'supporthelp' );

    $vars->{fullsearch} = $fullsearch;

    if ( $args->{user} || $args->{email} || $args->{userid} ) {
        my $dbr = LJ::get_db_reader();
        return error_ml( '/support/history.tt.error.nodatabase' ) unless $dbr;

        $vars->{get_user} = ( $args->{user} ) ? 1 : 0;
        $vars->{get_userid} = ( $args->{userid} ) ? 1 : 0;
        $vars->{get_email} = ( $args->{email} ) ? 1 : 0;
        $vars->{user} = $remote->user;

        my $reqlist;
        if ( $args->{user} || $args->{userid} ) {
            # get requests by a user, regardless of email (only gets user requests)
            my $userid = $args->{userid} ? $args->{userid}+0 : LJ::get_userid( LJ::trim( $args->{user} ) );
            return error_ml( '/support/history.tt.error.invaliduser' ) unless $userid
                && ( $fullsearch || $remote->id == $userid );
            $vars->{username} = LJ::ljuser( LJ::get_username( $userid ) );
            $reqlist = $dbr->selectall_arrayref(
                'SELECT spid, subject, state, spcatid, requserid, ' .
                       'timecreate, timetouched, timelasthelp, reqemail ' .
                'FROM support WHERE reqtype = \'user\' AND requserid = ?',
                undef, $userid );
        } elsif ( $args->{email} ) {
            # try by email, note that this gets requests opened by users and anonymous
            # requests, so we can view them all
            my $email = LJ::trim( $args->{email} );
            $vars->{email} = LJ::ehtml( $email );
            my %user_emails;

            unless ( $fullsearch ) {
                # check the list of allowable emails for this user
                my $query = "SELECT oldvalue FROM infohistory WHERE userid=? " .
                            "AND what='email' AND other='A'";
                my $rows = $dbr->selectall_arrayref( $query, undef, $remote->id );
                $user_emails{$_->[0]} = 1 foreach @$rows;
                $user_emails{$remote->email_raw} = 1 if $remote->email_status eq 'A';
            }

            return error_ml( '/support/history.tt.error.invalidemail' ) unless $email =~ /^.+\@.+$/
                && ( $fullsearch || $user_emails{$email} );
            $reqlist = $dbr->selectall_arrayref(
                'SELECT spid, subject, state, spcatid, requserid, ' .
                       'timecreate, timetouched, timelasthelp, reqemail ' .
                'FROM support WHERE reqemail = ?',
                undef, $email );
        }

        if ( @{$reqlist || []} ) {
            # construct a list of people who have answered these requests
            my @ids;
            foreach ( @$reqlist ) {
                next unless $_->[2] eq 'closed';
                push @ids, $_->[0];
            }
            my $idlist = join ',', map { $_+0 } @ids;
            my $winners = $dbr->selectall_arrayref( 'SELECT sp.spid, u.user, sp.points FROM useridmap u, supportpoints sp ' .
                                                   "WHERE u.userid = sp.userid AND sp.spid IN ($idlist)" );
            my %points;
            $points{$_->[0]+0} = [ $_->[1], $_->[2]+0 ] foreach @{$winners || []};

            # now construct the request blocks
            my %reqs;
            my @userids;
            foreach my $row ( @$reqlist ) {
                $reqs{$row->[0]} = {
                    spid => $row->[0],
                    winner => $points{$row->[0]}->[0],
                    points => $points{$row->[0]}->[1] || 0,
                    subject => LJ::ehtml($row->[1]),
                    state => $row->[2],
                    spcatid => $row->[3],
                    requserid => $row->[4],
                    timecreate => $row->[5],
                    timetouched => $row->[6],
                    timelasthelp => $row->[7],
                    reqemail => LJ::ehtml( $row->[8] ),
                };
                push @userids, $row->[4] if $row->[4];
            }
            my $us = @userids ? LJ::load_userids( @userids ) : undef;

            # get categories
            my $cats = LJ::Support::load_cats();

            foreach my $id ( sort { $a <=> $b } keys %reqs ) {
                # verify user can see this category (public_read or has supportread in it)
                next unless $cats->{$reqs{$id}->{spcatid}}{public_read} ||
                    LJ::Support::can_read_cat($cats->{$reqs{$id}->{spcatid}}, $remote);
                my $status = $reqs{$id}->{state} eq "closed" ? "closed" :
                             LJ::Support::open_request_status($reqs{$id}->{timetouched},
                                                              $reqs{$id}->{timelasthelp});
                my $answered = 0;
                my $points = 0;
                my $answeredby = '-';
                if ($reqs{$id}->{state} eq 'closed' && $reqs{$id}->{winner}) {
                    $answeredby = LJ::ljuser( $reqs{$id}->{winner} );
                    $points = $reqs{$id}->{points};
                    $answered = 1;
                }
                push @{ $vars->{reqs} }, {
                    spid => $reqs{$id}->{spid},
                    subject => $reqs{$id}->{subject},
                    status => $status,
                    answeredby => $answeredby,
                    points => $points,
                    answered => $answered,
                    catname => $cats->{$reqs{$id}->{spcatid}}{catname},
                    openedby => $reqs{$id}->{requserid} ? LJ::ljuser($us->{$reqs{$id}->{requserid}}) : $reqs{$id}->{reqemail},
                    timeopened => LJ::mysql_time( $reqs{$id}->{timecreate} )
                };
            }
        } else {
            $vars->{noresults} = 1;
        }
    } elsif ( $args->{fulltext} ) {
        $rv = DW::Controller::Support::Search::do_search(
                remoteid => $remote->id, query => $args->{fulltext} );
        return DW::Template->render_template( 'support/search.tt', $rv );

    } elsif ( ! $fullsearch ) {
        my $redirect_user = $remote->user;
        $r->header_out( Location => "$LJ::SITEROOT/support/history?user=$redirect_user" );
        return $r->REDIRECT;
    }

    return DW::Template->render_template( 'support/history.tt', $vars );

}

1;
