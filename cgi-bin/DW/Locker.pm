#!/usr/bin/perl
#
# DW::Locker
#
# Named advisory locks backed by MySQL GET_LOCK().  Replaces the inherited
# ddlockd daemon and DDLockClient, and is the single locking primitive for the
# site (the old LJ::DB::get_lock/release_lock were folded into this).
#
# Each lock gets its own dedicated, uncached master connection.  GET_LOCK is
# session-scoped, so a private connection per lock gives true mutual exclusion
# even within one process (two acquires of the same name contend against each
# other instead of both succeeding on a shared session), keeps the lock clear of
# ordinary query traffic, and lets a held lock be released by simply dropping
# the connection -- no RELEASE_LOCK bookkeeping and nothing to leak.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Locker;
use strict;
use warnings;

use Digest::MD5 qw( md5_hex );
use Time::HiRes ();
use DW::Stats;

our $Error;

sub new {
    my $class = shift;
    return bless {}, ( ref $class || $class );
}

# trylock( $name, wait => $secs ) -> DW::Lock on success, undef (and sets
# $Error) on failure.  Non-blocking by default; pass wait => N to block up to N
# seconds for the lock before giving up.
sub trylock {
    my ( $self, $name, %opts ) = @_;
    $Error = undef;

    my $wait  = $opts{wait} || 0;
    my $start = Time::HiRes::time();

    my $dbh = eval { LJ::get_dbh( { unshared => 1 }, "master" ) } or do {
        $Error = "no lock database available";
        _stat( 'error', $start );
        return undef;
    };

    # Don't silently reconnect into a fresh, lock-free session; and don't let an
    # idle hold (e.g. a multi-minute ljmaint task) get timed out and released.
    $dbh->{mysql_auto_reconnect} = 0;
    $dbh->do("SET SESSION wait_timeout = 2147483")
        or warn "DW::Locker: couldn't raise wait_timeout: " . ( $dbh->errstr || "?" ) . "\n";

    my $lockname = _lockname($name);
    my ($got) = $dbh->selectrow_array( "SELECT GET_LOCK(?, ?)", undef, $lockname, $wait );

    # 1 = acquired, 0 = held elsewhere (or timed out), undef = error/killed.
    unless ($got) {
        $Error = defined $got ? "lock taken" : "GET_LOCK error: " . ( $dbh->errstr || "?" );
        _stat( defined $got ? 'taken' : 'error', $start );
        return undef;
    }

    _stat( 'acquired', $start );
    return DW::Lock->new($dbh);
}

# Emit acquire metrics tagged by outcome (acquired / taken / error) so a
# contended or failing lock shows up on its own series. The timing VALUE is
# milliseconds (statsd "ms" type), but the Prometheus statsd_exporter converts
# "ms" timers to base-unit seconds, so the metric is named *_seconds to match
# what it stores (same convention as dw.task.duration_seconds). The duration
# spans the whole attempt -- connect, session setup, and GET_LOCK -- so it also
# surfaces the per-lock connection cost and any blocking wait.
sub _stat {
    my ( $outcome, $start ) = @_;
    my $tags = ["outcome:$outcome"];
    DW::Stats::increment( 'dw.locker.acquire', 1, $tags );
    DW::Stats::timing( 'dw.locker.acquire_duration_seconds',
        ( Time::HiRes::time() - $start ) * 1000, $tags );
}

# Map a caller name to a valid GET_LOCK name: prefix "dwl:" to keep our locks in
# their own namespace, and stay within MySQL's 64-char limit by hashing anything
# too long (names are usually short and stay readable in SHOW PROCESSLIST /
# performance_schema.metadata_locks).
sub _lockname {
    my $name = shift;
    my $key  = "dwl:$name";

    # use the name as-is when it's short and all printable ASCII; otherwise
    # hash it to stay within GET_LOCK's 64-char limit.
    return $key if length($key) <= 64 && $key =~ /\A[\x20-\x7e]*\z/;
    return "dwl:" . md5_hex($name);    # 4 + 32 = 36 chars
}

#####################################################################
package DW::Lock;
use strict;
use warnings;

# A held lock owns the dedicated connection that holds it.  Dropping the
# connection ends the session, which auto-releases the GET_LOCK.
sub new {
    my ( $class, $dbh ) = @_;
    return bless { dbh => $dbh, pid => $$ }, $class;
}

sub release {
    my $self = shift;
    my $dbh  = delete $self->{dbh} or return;
    $dbh->disconnect;
}

sub DESTROY {
    my $self = shift;

    # Never clobber the caller's $@/$!/$? while unwinding, and don't let a forked
    # child release a lock its parent still holds (it shares the inherited fd).
    local ( $@, $!, $? );
    $self->release if $$ == $self->{pid};
}

1;
