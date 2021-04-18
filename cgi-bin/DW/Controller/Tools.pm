#!/usr/bin/perl
#
# DW::Controller::Tools
#
#
# Authors:
#      RSH <ruth.s.hatch@gmail.com
#
# Copyright (c) 2009-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Tools;
use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use HTTP::Date; # str2time

DW::Routing->register_string( '/tools/comment_crosslinks', \&crosslinks_handler, app => 1 );
DW::Routing->register_string( '/tools/recent_email', \&recent_email_handler, app => 1 );
DW::Routing->register_string( '/tools/recent_emailposts', \&recent_emailposts_handler, app => 1 );
DW::Routing->register_string( '/tools/opml', \&opml_handler, app => 1 );
DW::Routing->register_string( '/tools/emailmanage', \&emailmanage_handler, app => 1 );

sub crosslinks_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $u = $rv->{u};

    my $dbcr = LJ::get_cluster_reader($u) or die;

    my $props = $dbcr->selectall_arrayref(
        q{
select
    l.jitemid * 256 + l.anum as 'ditemid',
    t.jtalkid * 256 + l.anum as 'dtalkid',
    tp.value
from
    log2 l
       inner join talk2 t on (t.journalid = l.journalid and l.jitemid = t.nodeid and t.nodetype = 'L')
       inner join talkprop2 tp on (tp.journalid = t.journalid and t.jtalkid = tp.jtalkid)
where
    tp.tpropid = 13 and tp.journalid = ?
		}, undef, $u->id
    );

    my $base = $u->journal_base;

    my $vars = { 'base' => $base, 'props' => $props, 'authas_html' => $rv->{authas_html} };
    return DW::Template->render_template( 'tools/comment_crosslinks.tt', $vars );
}

sub recent_email_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;
    my $r      = DW::Request->get;
    my $u = $rv->{u};

    my $is_admin = $u->has_priv( "siteadmin", "emailqueue" );
    my $email;

    if ($is_admin) {
        my $what = $r->get_args->{'what'} || $r->post_args->{'what'};
        if ($what =~ /@/) { # looking up an email address
            $email = $what;
        } else { # looking up a user
            $what = LJ::canonical_username($what);
            $u = LJ::load_user($what) if $what;
            return LJ::error_list("There is no user $what")
                unless $u;
        }

        $email ||= $u->email_raw;
        my ($username, $domain) = $email =~ /(.*)\@(.*)/;

        # TODO: Figure out how to make this work when TheSchwartz has gone away
        # and is no longer being used for stuff.
        my $sclient = LJ::theschwartz();
        my @jobs = $sclient->list_jobs({
            funcname    => 'TheSchwartz::Worker::SendEmail',
            coalesce_op => 'LIKE',
            coalesce    => "$domain\@$username",
            want_handle => 1
            });

        my @cleaned_jobs;
        foreach my $job (sort { $a->run_after <=> $b->run_after } @jobs) {
            my $email = $job->arg->{data};
            my ($subject) = $email =~/Subject:(.*)/;

            my $temp = {
                subject => $subject,
                jobid => $job->jobid,
                run_after => LJ::time_to_http($job->run_after)
            };

            if ($job->failures) {
                $temp->{failures} = $job->handle->failure_log;
            }

            push @cleaned_jobs, $temp;
        }

        my $vars = { 'what' => $what, 'jobs' => \@cleaned_jobs };
        return DW::Template->render_template( 'tools/recent_email.tt', $vars );
    } else {
        $r->add_msg("You do not have access to use this page.", $r->WARNING);
        return $r->redirect($LJ::SITEROOT);
    }

}

sub recent_emailposts_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $remote = $rv->{remote};
    my $r      = DW::Request->get;
    my  $vars = {};

    unless ($LJ::EMAIL_POST_DOMAIN) {
        $r->add_msg("Sorry, this site is not configured to use the emailgateway.", $r->WARNING);
        return $r->redirect($LJ::SITEROOT);
    }

    my $admin = $remote->has_priv( 'supporthelp' );
    $vars->{admin} = $admin;

    my $u;
    if ( $admin ) {
        my $user = $r->post_args->{user} || $r->get_args->{user};
        $u = LJ::load_user($user);
        $vars->{user} = $user;
    }

    $u ||= $remote;

    if ($u) {
        my @clean_rows;
        my $dbcr = LJ::get_cluster_reader( $u );
        my $sql = qq{
            SELECT
                logtime, extra,
                DATE_FORMAT(FROM_UNIXTIME(logtime), "%M %D %Y, %l:%i%p") AS ftime
            FROM userlog
            WHERE userid=?
                AND action='emailpost'
            ORDER BY logtime DESC LIMIT 50
        };
        my $data = $dbcr->selectall_hashref( $sql, 'logtime', undef, $u->{userid} );

        foreach ( reverse sort keys %$data ) {
            my $row = {};
            LJ::decode_url_string( $data->{$_}->{extra}, $row );
            
            my $err;
            if ($row->{e}) {
                $err = '<strong>Yes</strong>';
                $err .= ' (will retry)' if $row->{retry};
            } else {
                $err = 'None';
            }
            my $temp = {
                when => $data->{$_}->{ftime},
                type => ($row->{t} || "entry"),
                subj => $row->{s},
                err => $err,
                msg => ($row->{m} ? LJ::ehtml($row->{m}) : 'Post success.')
            };
            push @clean_rows, $temp;
        }

        $vars->{data} = \@clean_rows;
    } else {
        $r->add_msg("No such user.", $r->WARNING);
    }

    return DW::Template->render_template( 'tools/recent_emailposts.tt', $vars );

}

sub opml_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $remote = $rv->{remote};
    my $r      = DW::Request->get;
    my $get_args = $r->get_args;
    my $user = $get_args->{user};

    # if we don't have a current user but somebody is logged in, redirect
    # them to their own OPML page
    if ( $remote && !$user ) {
        return BML::redirect( "$LJ::SITEROOT/tools/opml?user=$remote->{user}" );
    }

    return "No 'user' argument" unless $user;

    my $u = LJ::load_user_or_identity( $user )
        or return "Invalid user.";

    my @uids;

    # different accounts need different userid loads
    # will use watched accounts for personal accounts
    # and identity accounts
    # and members for communities
    if( $u->is_person || $u->is_identity ) {
        @uids = $u->watched_userids;
    } elsif( $u->is_community ) {
        @uids = $u->member_userids;
    } else {
        return "Invalid account type.";
    }

    my $us  = LJ::load_userids( @uids );

    DW::Stats::increment( 'dw.opml.used', 1 );
    my @cleaned;

    # currently ordered by user ID; there might be a better way to order this
    # but unless somebody has a strong preference about it there's no point
    foreach my $uid ( sort { $a <=> $b } @uids ) {
        my $w = $us->{$uid} or next;

        # identity accounts do not have feeds
        next if $w->is_identity;
        # filter by account type
        next if $get_args->{show} && ! ( $get_args->{show} =~ /[P]/ && $w->is_person
                    || $get_args->{show} =~ /[C]/ && $w->is_community
                    || $get_args->{show} =~ /[YF]/ && $w->is_syndicated );

        my $title;

        # use the username + site abbreviation for each feed's title if we have that
        # option set
        if( $get_args->{title} eq "username" ) {
            $title = $w->display_username . " (" . $LJ::SITENAMEABBREV . ")";
        } else {
            # FIXXME: Should be using a function call instead! But $w->prop( "journaltitle" )
            # returns empty here, though it's used in profile.bml
            $title = $w->{name};
        }

        my $feed;

        if ( $w->is_syndicated ) {
            my $synd = $w->get_syndicated;
            $feed = $synd->{synurl};
        } else {
            $feed = $w->journal_base;

            if( $get_args->{feed} eq "atom" ) {
                $feed .= "/data/atom";
            } else {
                $feed .= "/data/rss";
            }

            if( $get_args->{auth} eq "digest" ) {
                $feed .= "?auth=digest";
            }
        }
        push @cleaned, {title => $title, feed => $feed };
    }

    my $vars = { 
        'u' => $u, 
        'uids' => \@cleaned, 
        'email_visible' => $u->email_visible($remote) 
        };

    my $opml = DW::Template->template_string( 'tools/opml.tt', $vars, { no_sitescheme => 1 } );
    $r->content_type("text/plain");
    $r->print($opml);
    return $r->OK;
}

sub emailmanage_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $remote = $rv->{remote};
    my $r      = DW::Request->get;

    my $dbh = LJ::get_db_writer();
    my $authas = $r->get_args->{'authas'} || $remote->{'user'};
    my $u = LJ::get_authas_user($authas);
    return error_ml('error.invalidauth')
        unless $u;

    # at the point that the latest email has been on the account for 6 months, *all* previous emails should become removable. 
    # They should be able to remove all other email addresses at that point if multiple ones are listed, 
    # so that they can remove anything that might potentially be compromised, leaving only their current/secured email on the account.
    # - Anne Zell, 11 december 2008 in LJSUP-3193, based on discussions in lj_core

    my $firstdate = $dbh->selectrow_array(qq{
        SELECT MIN(timechange) FROM infohistory
        WHERE userid=? AND what='email'
        AND oldvalue=?
    }, undef, $u->{'userid'}, $u->email_raw);

    my $lastdate_email = $dbh->selectrow_array(qq{
        SELECT MAX(timechange) FROM infohistory
        WHERE userid=? AND (what='email' OR what='emaildeleted' AND length(other)<=2)
    }, undef, $u->{'userid'});

    my $lastdate_deleted = $dbh->selectrow_array(qq{
        SELECT MAX(SUBSTRING(other FROM 3)) FROM infohistory
        WHERE userid=? AND what='emaildeleted'
    }, undef, $u->{'userid'});

    my $lastdate = defined $lastdate_deleted ? ($lastdate_email gt $lastdate_deleted ? $lastdate_email : $lastdate_deleted) : $lastdate_email;

    # current address was set more, than 6 months ago?
    my $six_month_case = time() - str2time($lastdate) > 182 * 24 * 3600; # half year

    my @deleted;
    if ($r->did_post && $u->{'status'} eq 'A') {
        my $sth = $dbh->prepare("SELECT timechange, oldvalue " .
                                "FROM infohistory WHERE userid=? " . 
                                "AND what='email' ORDER BY timechange");
        $sth->execute($u->{'userid'});
        while (my ($time, $email) = $sth->fetchrow_array)
        {
            my $can_del = defined $firstdate && $time gt $firstdate || $six_month_case;
            if ($can_del && $r->post_args->{"$email-$time"}) {
                push @deleted, LJ::Lang::ml('/tools/emailmanage.tt.log.deleted', 
                                       { 'email' => $email,
                                         'time' => $time });

                $dbh->do("UPDATE infohistory SET what='emaildeleted', other=CONCAT(other, ';', timechange), timechange = NOW() " .
                         "WHERE what='email' AND userid=? AND timechange=? AND oldvalue=?",
                         undef, $u->{'userid'}, $time, $email);
            }            
        }
    }

    my $sth = $dbh->prepare("SELECT timechange, oldvalue FROM infohistory " .
                            "WHERE userid=? AND what='email' " .
                            "ORDER BY timechange");
    $sth->execute($u->{'userid'});
    my @rows;
    while (my ($time, $email) = $sth->fetchrow_array)
    {
        my $can_del = defined $firstdate && $time gt $firstdate || $six_month_case;
        push @rows, {email => $email, time => $time, can_del => $can_del};

    }

    my $vars = { 
        'u' => $u, 
        'lastdate' => $lastdate, 
        'authas_html' => $rv->{authas_html},
        'deleted' => \@deleted,
        'rows' => \@rows,
        'getextra'=> ($authas ne $remote->{'user'} ? "?authas=$authas" : '')
         };
    return DW::Template->render_template( 'tools/emailmanage.tt', $vars );
}

1;
