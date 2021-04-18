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

DW::Routing->register_string( '/tools/comment_crosslinks', \&crosslinks_handler, app => 1 );
DW::Routing->register_string( '/tools/recent_email', \&recent_email_handler, app => 1 );
DW::Routing->register_string( '/tools/recent_emailposts', \&recent_emailposts_handler, app => 1 );

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

1;
