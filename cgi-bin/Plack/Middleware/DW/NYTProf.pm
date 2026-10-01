#!/usr/bin/perl
#
# Plack::Middleware::DW::NYTProf
#
# On-demand request profiler. When an admin appends ?nytprof=1 on a canary or
# dev server, this profiles just that request with Devel::NYTProf and returns the
# flamegraph SVG in place of the page, so we can see where a request spends its
# wall-clock time (DB, memcache, rendering). The rest of the generated HTML report
# is kept on disk and served under /nytprof/<id>/ so the flamegraph's per-line
# drill-down links work. Reports are pruned by age to bound disk use.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::NYTProf;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;

use File::Path qw/ make_path remove_tree /;

use DW::Request;

# nytprofhtml ships with Devel::NYTProf in extlib/bin. It runs nytprofcalls +
# flamegraph.pl under the hood and writes the flamegraph SVG (below) plus the
# per-line HTML report into its --out directory.
my $NYTPROFHTML = "$ENV{LJHOME}/extlib/bin/nytprofhtml";
my $FLAMEGRAPH  = 'all_stacks_by_time.svg';

# Generated reports live here. This is on local disk shared by every worker in
# the (single) web task, so any worker can serve a report another one generated.
my $REPORT_BASE = "/tmp/nytprof-reports";

# Prune reports older than this on each new capture, so /tmp doesn't grow without
# bound. This is a manual debugging tool, so a short window is plenty.
my $RETENTION = 3600;

# Per-worker sequence, combined with time + pid for a unique, path-safe report id.
my $seq = 0;

sub call {
    my ( $self, $env ) = @_;

    # Inert unless the worker was booted with the profiler loaded. bin/starman
    # only re-execs under -d:NYTProf when DW_NYTPROF is set, so on a normal worker
    # DB::enable_profile doesn't exist and this whole module is a pass-through.
    return $self->app->($env) unless defined &DB::enable_profile;

    my $r = DW::Request->get;

    # Serve a previously-generated report file (flamegraph links point here).
    if ( $r && ( my ( $id, $file ) = $r->path =~ m{^/nytprof/([\w-]+)/(.+)$} ) ) {
        return $self->_serve_report( $id, $file ) if $self->_may_view;
        return $self->app->($env);    # not permitted -> fall through to normal 404
    }

    return $self->app->($env) unless $self->_wants_profile;

    make_path($REPORT_BASE);
    my $id  = sprintf( '%d-%d-%d', time(), $$, $seq++ );
    my $dir = "$REPORT_BASE/$id";
    my $out = "$REPORT_BASE/$id.out";

    DB::enable_profile($out);
    my $res = eval { $self->app->($env) };
    my $err = $@;

    # ALWAYS stop and flush, even when the app died. NYTProf's profiling state is
    # process-global; leaving it enabled would profile (and corrupt the file for)
    # the next request this worker serves.
    DB::disable_profile();
    DB::finish_profile();

    # If the request itself blew up, preserve normal error handling rather than
    # serve a flamegraph of a half-finished request.
    if ($err) {
        unlink $out;
        die $err;
    }

    $self->_prune;
    my $svg = $self->_build_report( $out, $dir, $id );
    unlink $out;

    # If report generation failed for any reason, fall back to the real page so
    # the flag can never turn a working page into an error.
    return $res unless defined $svg;

    return [
        200,
        [
            'Content-Type'  => 'image/svg+xml; charset=utf-8',
            'Cache-Control' => 'no-store',
        ],
        [$svg],
    ];
}

# Profile only when the caller both asks for it and is allowed to. Restricted to
# canary/dev tiers AND site admins: profiling adds latency and the report exposes
# internal package/sub names (and source), so it must never be reachable by
# ordinary visitors even on canary.
sub _wants_profile {
    my $self = shift;

    my $r = DW::Request->get or return 0;
    return 0 unless $r->get_args->{nytprof};
    return $self->_may_view;
}

# Gate for both generating and viewing reports. On a dev server we allow it
# outright, matching the loose ?as= impersonation model dev already uses (and dev
# isn't public). On canary, require a real logged-in admin -- the follow-up report
# requests carry the admin's session, so their drill-down links stay gated.
sub _may_view {
    my $self = shift;

    return 0 unless $LJ::IS_CANARY || $LJ::IS_DEV_SERVER;
    return 1 if $LJ::IS_DEV_SERVER;

    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( 'admin', '*' ) ? 1 : 0;
}

# Run nytprofhtml over the profile into $dir, then return the flamegraph SVG with
# its relative drill-down links rewritten to absolute /nytprof/<id>/ URLs (the SVG
# itself is served from the page's path, not from the report dir). Returns undef
# on any failure so the caller can fall back to the real page.
sub _build_report {
    my ( $self, $out, $dir, $id ) = @_;

    unless ( -x $NYTPROFHTML ) {
        $log->warn("nytprofhtml not found at $NYTPROFHTML; is Devel::NYTProf installed?");
        return undef;
    }

    # Run with extlib in @INC so nytprofhtml finds Devel::NYTProf::*, but clear
    # PERL5OPT first so the -d:NYTProf we boot the worker with doesn't make the
    # report generator profile itself. nytprofhtml shells out to its siblings
    # (nytprofcalls, flamegraph.pl) by searching PATH, so extlib/bin must be on it.
    local $ENV{PERL5OPT} = '';
    local $ENV{NYTPROF}  = '';
    local $ENV{PATH}     = "$ENV{LJHOME}/extlib/bin:$ENV{PATH}";
    my $rc = system( $^X, "-I$ENV{LJHOME}/extlib/lib/perl5",
        $NYTPROFHTML, '--file', $out, '--out', $dir );
    if ( $rc != 0 ) {
        $log->warn("nytprofhtml exited with status $rc");
        return undef;
    }

    my $svg_path = "$dir/$FLAMEGRAPH";
    open my $fh, '<', $svg_path or do {
        $log->warn("flamegraph not produced at $svg_path: $!");
        return undef;
    };
    local $/;
    my $svg = <$fh>;
    close $fh;

    # Frame links are relative (e.g. "e-1-line.html#1") and resolve against the
    # report dir, but this SVG is returned inline from the profiled page's own
    # path. Rewrite relative (x)links to the report's served location so clicking
    # a frame lands on the right per-line report.
    $svg =~ s{((?:xlink:)?href)="(?!https?://|/|#)([^"]+)"}{$1="/nytprof/$id/$2"}g;

    return $svg;
}

# Serve one file out of a generated report directory. Guards against path
# traversal and only serves regular files that actually live under $REPORT_BASE.
sub _serve_report {
    my ( $self, $id, $file ) = @_;

    return _not_found() if $file =~ m{(?:^|/)\.\.(?:/|$)};

    my $path = "$REPORT_BASE/$id/$file";
    return _not_found() unless -f $path;

    open my $fh, '<', $path or return _not_found();
    binmode $fh;
    local $/;
    my $body = <$fh>;
    close $fh;

    return [
        200,
        [
            'Content-Type'  => _content_type($file),
            'Cache-Control' => 'no-store',
        ],
        [$body],
    ];
}

# Delete report directories (and any stray .out files) older than $RETENTION.
sub _prune {
    my $self = shift;

    opendir my $dh, $REPORT_BASE or return;
    my $cutoff = time() - $RETENTION;
    while ( my $entry = readdir $dh ) {
        next if $entry eq '.' || $entry eq '..';
        my $path  = "$REPORT_BASE/$entry";
        my $mtime = ( stat $path )[9];
        next unless defined $mtime && $mtime < $cutoff;
        if    ( -d $path ) { remove_tree($path) }
        elsif ( -f $path ) { unlink $path }
    }
    closedir $dh;
}

sub _content_type {
    my $file = shift;
    return 'text/html; charset=utf-8'     if $file =~ /\.html?$/;
    return 'image/svg+xml; charset=utf-8' if $file =~ /\.svg$/;
    return 'text/css'                     if $file =~ /\.css$/;
    return 'application/javascript'       if $file =~ /\.js$/;
    return 'text/plain; charset=utf-8';
}

sub _not_found {
    return [ 404, [ 'Content-Type' => 'text/plain' ], ['Not found'] ];
}

1;
