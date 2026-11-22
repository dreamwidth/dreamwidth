#!/usr/bin/perl
#
# DW::Controller::Admin::Importer
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

package DW::Controller::Admin::Importer;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

use DW::Importer::Control;
use DW::Importer::LogStore;
use DW::Importer::Queue;
use DW::Importer::Registry;
use DW::Logic::Importer;

# viewing the queue and details for a specific import
DW::Routing->register_string( "/admin/importer/queue/index",   \&queue_controller );
DW::Routing->register_string( "/admin/importer/details/index", \&detail_controller );

DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'importer/queue',
    ml_scope => '/admin/importer.tt',
    privs    => ['siteadmin:theschwartz']
);

# view overall import history, and act on it
DW::Routing->register_string( "/admin/importer/history/index", \&history_controller );
DW::Routing->register_string( "/admin/importer/log",           \&log_controller );

DW::Controller::Admin->register_admin_page(
    '/',,
    path     => 'importer/history',
    ml_scope => '/admin/importer/history.tt',
    privs    => ['siteadmin:importhistory']
);

sub queue_controller {
    my ( $ok, $rv ) = controller( privcheck => ["siteadmin:theschwartz"] );
    return $rv unless $ok;

    my $vars    = {};
    my $sclient = LJ::theschwartz();
    my @joblist = $sclient->list_jobs( { funcname => [ DW::Importer::Registry->classes ] } );

    my @latest;
    my @jobs;
    foreach my $job (@joblist) {
        my $funcname  = $job->funcname;
        my $arg       = $job->arg;
        my $u         = LJ::load_userid( $arg->{userid} );
        my $latest_id = DW::Logic::Importer->get_import_data_for_user($u)->[0]->[0];

        push @latest, [ $u, $latest_id ];

        push @jobs,
            {
            type     => $funcname,
            user     => $u->ljuser_display,
            username => $u->username,
            importid => { job => $arg->{import_data_id}, latest => $latest_id },
            };
    }
    $vars->{jobs} = \@jobs;

    return DW::Template->render_template( 'admin/importer.tt', $vars );
}

sub detail_controller {
    my ( $ok, $rv ) = controller( privcheck => ["siteadmin:theschwartz"] );
    return $rv unless $ok;

    my $get  = DW::Request->get->get_args;
    my $user = $get->{user};

    my $u = LJ::load_user($user);
    return error_ml("error.invaliduser") unless $u;

    my $items = DW::Logic::Importer->get_queued_imports($u);
    my $data  = DW::Logic::Importer->get_import_data( $u, keys %$items );

    # 1. iterate over every import to get the user/host info
    # 2. iterate over every job in that import to add the user/host info
    foreach my $row (@$data) {
        my ( $importid, $host, $user, $usejournal ) = @$row;
        my $source = sprintf( "%s@%s", $usejournal || $user, $host );

        foreach my $key ( keys %{ $items->{$importid} } ) {
            $items->{$importid}->{$key}->{source} = $source;
        }
    }

    my $vars = { username => $u->ljuser_display, import_items => $items };

    if ( scalar keys %{ $items || {} } > 1 ) {
        $vars->{errmsg} = ".error.toomanypending";
    }

    return DW::Template->render_template( 'admin/importer/detail.tt', $vars );
}

my $HISTORY_PRIV = 'siteadmin:importhistory';

# the page is the way to cancel or rerun an import, so it takes POSTs, with form auth checked
# before anything is read from them
sub history_controller {
    my ( $ok, $rv ) = controller( privcheck => [$HISTORY_PRIV], form_auth => 1 );
    return $rv unless $ok;

    my $r    = DW::Request->get;
    my $args = $r->did_post ? $r->post_args : $r->get_args;
    my $user = $args->{user};

    my $vars = { remote => $rv->{remote}, formdata => $args };

    if ( defined $user && length $user ) {
        my $u = LJ::load_user($user);
        return error_ml("error.invaliduser") unless $u;

        $vars->{result}   = _history_action( $rv->{remote}, $u, $args ) if $r->did_post;
        $vars->{u}        = $u;
        $vars->{username} = $u->ljuser_display;
        $vars->{imports}  = _history_for($u);
    }

    return DW::Template->render_template( 'admin/importer/history.tt', $vars );
}

# Does what a POST of the history page asks for: action is cancel, retry or rerun (one
# item). Returns what the page shows: { action, import_data_id, [ error | data ] }.
sub _history_action {
    my ( $remote, $u, $args ) = @_;

    my $action = $args->{action}         // '';
    my $id     = $args->{import_data_id} // '';
    my %result = ( action => $action, import_data_id => $id );

    return { %result, error => 'badaction' } unless $action =~ /^(?:cancel|retry|rerun)$/;
    return { %result, error => 'badimport' }
        unless $id =~ /^\d+$/ && exists DW::Logic::Importer->get_all_import_items($u)->{$id};

    if ( $action eq 'cancel' ) {
        return { %result, data => DW::Importer::Control->cancel( $u, $id, actor => $remote ) };
    }

    my $res = DW::Importer::Control->retry(
        $u, $id,
        actor => $remote,
        $action eq 'rerun' ? ( items => [ $args->{item} // '' ] ) : ()
    );
    return { %result, error => $res->{error} } if $res->{error};
    return { %result, data  => $res };
}

# every import of the user, newest first, with what the page shows for each
sub _history_for {
    my ($u) = @_;

    my $items       = DW::Logic::Importer->get_all_import_items($u);
    my $data        = DW::Logic::Importer->get_import_data( $u, keys %$items );
    my %import_data = map { $_->[0] => $_ } @$data;

    my $now   = time();
    my $order = 0;
    my %order = map { $_->{name} => $order++ } DW::Importer::Registry->items;

    my @imports;
    foreach my $id ( sort { $b <=> $a } keys %$items ) {
        my ( $host, $source_user, $usejournal ) = @{ $import_data{$id} || [] }[ 1 .. 3 ];
        my ( $jobs, $queue_complete ) = DW::Importer::Queue->jobs_for_import( $u, $id );

        my %logs;
        my $logs = eval { DW::Importer::LogStore->logs_for( $u->id, $id ) };
        warn "Unable to list import logs: $@" if $@;
        push @{ $logs{ $_->{item} } }, $_ foreach @{ $logs || [] };

        my @rows;
        foreach my $name (
            sort { ( $order{$a} // 1e9 ) <=> ( $order{$b} // 1e9 ) || $a cmp $b }
            keys %{ $items->{$id} }
            )
        {
            my $row  = $items->{$id}->{$name};
            my @jobs = map {
                {
                    %$_, state => $_->{running} ? 'running'
                        : ( $_->{failures} && $_->{run_after} > $now ) ? 'retry'
                        : 'waiting'
                }
            } @{ $jobs->{$name} || [] };

            push @rows, { name => $name, %$row, jobs => \@jobs, logs => $logs{$name} || [] };
            delete $logs{$name};
        }

        my @statuses = map { $_->{status} } @rows;
        push @imports,
            {
            id             => $id,
            source         => $host ? sprintf( '%s@%s', $usejournal || $source_user, $host ) : '',
            created        => ( sort { $a <=> $b } map { $_->{created} } @rows )[0],
            items          => \@rows,
            other_logs     => [ map { @$_ } values %logs ],
            queue_complete => $queue_complete,
            can_cancel     => ( grep { /^(?:init|ready|queued)$/ } @statuses ) ? 1 : 0,
            retry_refusal  => DW::Importer::Control->retry_refusal( $u, $id ),
            };
    }

    return \@imports;
}

my $LOG_SCOPE = '/admin/importer/log.tt';

# one import log, shown in the page or, with format=text, as a plain-text download
sub log_controller {
    my ( $ok, $rv ) = controller( privcheck => [$HISTORY_PRIV] );
    return $rv unless $ok;

    my $r    = DW::Request->get;
    my $args = $r->get_args;

    my $u = LJ::load_user( $args->{user} // '' )
        or return error_ml("error.invaliduser");

    # the log has to be the named user's, or the user in the URL says nothing about whose it is
    my $logid = $args->{logid} // '';
    my $log   = $logid =~ /^\d+$/ ? DW::Importer::LogStore->log($logid) : undef;
    return error_ml("$LOG_SCOPE.error.nolog")
        unless $log && $log->{userid} == $u->id;

    # UTF-8 bytes, which is what the templates and the response both take
    my ( $text, $missing ) = DW::Importer::LogStore->content($log);

    if ( ( $args->{format} // '' ) eq 'text' ) {
        $r->content_type('text/plain; charset=utf-8');
        $r->print($text);
        return $r->OK;
    }

    return DW::Template->render_template(
        'admin/importer/log.tt',
        {
            u        => $u,
            username => $u->ljuser_display,
            log      => $log,
            text     => $text,
            missing  => $missing,
        }
    );
}

1;
