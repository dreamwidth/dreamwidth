#!/usr/bin/perl
#
# DW::Task::SearchCopier
#
# Copies content into Manticore Search (RT mode). Parallel to
# DW::Task::SphinxCopier, which writes to the legacy dw_sphinx
# MySQL staging DB; both run side-by-side during the migration.
# Routes to its own SQS queue automatically via class-name derivation.
#
# Arg shape (hashref in args->[0]):
#   { userid => N }                         # full recopy (24h throttled)
#   { userid => N, jitemid => J }           # one entry; handles deletes
#   { userid => N, jtalkid => T }           # one comment; handles deletes
#   { userid => N, force => 1 }             # skip throttle on full recopy
#   { userid => N, source => 'label' }      # optional provenance for logs
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::SearchCopier;

use strict;
use v5.10;
use DW::Task;    # must come before `use base` so COMPLETED/FAILED
                 # constants are defined before this file's body
                 # compiles under strict
use base 'DW::Task';

use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DBI;
use Encode;

sub work {
    my ( $self, $handle ) = @_;
    my $args = $self->args->[0];

    $self->{stats} = {
        entries_ok   => 0,
        entries_err  => 0,
        comments_ok  => 0,
        comments_err => 0,
        deletes_ok   => 0,
        deletes_err  => 0,
    };

    my $u = LJ::load_userid( $args->{userid} )
        or do {
        $log->warn("SearchCopier: invalid userid $args->{userid}");
        return DW::Task::COMPLETED;
        };

    $log->info( "Search copier started for "
            . $u->user . "("
            . $u->id
            . "), source "
            . ( $args->{source} // 'unknown' )
            . "." );

    return DW::Task::COMPLETED unless $u->is_person || $u->is_community;
    return DW::Task::COMPLETED if $u->is_expunged;

    my $copy_comments = $u->is_paid ? 1 : 0;

    if ( exists $args->{jitemid} ) {
        $log->info("Requested copy of only entry $args->{jitemid}.");
        $self->_import_one_entry( $u, $args->{jitemid} );
    }
    elsif ( exists $args->{jtalkid} ) {
        $log->info("Requested copy of only comment $args->{jtalkid}.");
        $self->_import_one_comment( $u, $args->{jtalkid} ) if $copy_comments;
    }
    else {
        $log->info("Requested complete recopy of user.");

        # Full recopy. 24h throttle (independent from SphinxCopier's) unless
        # the caller explicitly bypasses.
        unless ( $args->{force} ) {
            my $k    = [ $u->id, 'search-copy-full:' . $u->id ];
            my $last = LJ::MemCache::get($k);
            if ( $last && $last > time() - 86400 ) {
                $log->info("Copied less than a day ago. Skipping.");
                return DW::Task::COMPLETED;
            }
            LJ::MemCache::set( $k, time() );
        }
        $self->_import_full( $u, $copy_comments );
    }

    my $s       = $self->{stats};
    my $err_sum = $s->{entries_err} + $s->{comments_err} + $s->{deletes_err};
    my $summary = sprintf
        'SearchCopier: %s(%d) done: entries=%d(err %d) comments=%d(err %d) deletes=%d(err %d)',
        $u->user, $u->id,
        $s->{entries_ok},  $s->{entries_err},
        $s->{comments_ok}, $s->{comments_err},
        $s->{deletes_ok},  $s->{deletes_err};
    if   ($err_sum) { $log->warn($summary) }
    else            { $log->debug($summary) }

    return DW::Task::COMPLETED;
}

sub stats { return $_[0]->{stats} }

# -----------------------------------------------------------------------------
# Manticore connection and encoding helpers.
# -----------------------------------------------------------------------------

sub _dbh {
    die "\@LJ::MANTICORE is not configured\n" unless @LJ::MANTICORE;
    my ( $host, undef, $sql_port ) = @LJ::MANTICORE;
    return DBI->connect(
        "DBI:mysql:host=$host;port=$sql_port",
        undef, undef,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
            PrintError        => 0,
            mysql_enable_utf8 => 1,
        },
    );
}

# Mirrors DW::Task::SphinxCopier's bit-layout so the search worker's
# filter contract stays intact: bit_breakdown(allowmask) + sentinels
# (101 = private, 102 = public). usemask with no groups collapses to
# private, matching the legacy behavior.
sub _security_bits {
    my ( $security, $allowmask ) = @_;
    $security = 'private'
        if $security eq 'usemask' && $allowmask == 0;

    my @extra;
    push @extra, 101 if $security eq 'private';
    push @extra, 102 if $security eq 'public';

    return [ LJ::bit_breakdown($allowmask), @extra ];
}

# Multi-value attribute literal for SphinxQL: (1,2,3). Assumes all ints.
sub _mva {
    return '(' . join( ',', @{ $_[0] } ) . ')';
}

# UTF-8 decode helper matching what the legacy copier does to text pulled
# from log2/talk2 — LJ::text_uncompress is idempotent on non-compressed
# input, and Encode::decode turns raw-bytes-that-are-utf8 into a Perl
# character string.
sub _decode_text {
    my $ref = shift;
    LJ::text_uncompress($ref);
    $$ref = Encode::decode( 'utf8', $$ref );
    return $$ref;
}

# _insert_* and _delete_* return 1 on success, 0 on failure (logged).
# Callers use the return to increment stats.

sub _insert_entry {
    my ( $dbh, $row ) = @_;
    my $sql = sprintf(
        'INSERT INTO dw1 (journalid, jitemid, jtalkid, poster_id, date_posted,'
            . ' allow_global_search, is_deleted, security_bits, title, body)'
            . ' VALUES (%d, %d, 0, %d, %d, %d, 0, %s, ?, ?)',
        $row->{journalid},   $row->{jitemid},      $row->{poster_id},
        $row->{date_posted}, $row->{allow_global}, _mva( $row->{bits} ),
    );

    # Manticore RT rejects NULL in VALUES; undef title/body must go in as ''.
    my $ok = eval {
        $dbh->do( $sql, {}, ( $row->{title} // '' ), ( $row->{body} // '' ) );
        1;
    };
    unless ($ok) {
        $log->warn( sprintf 'insert entry journalid=%d jitemid=%d failed: %s',
            $row->{journalid}, $row->{jitemid}, $@ );
    }
    return $ok ? 1 : 0;
}

sub _insert_comment {
    my ( $dbh, $row ) = @_;
    my $sql = sprintf(
        'INSERT INTO dw1 (journalid, jitemid, jtalkid, poster_id, date_posted,'
            . ' allow_global_search, is_deleted, security_bits, title, body)'
            . ' VALUES (%d, %d, %d, %d, %d, %d, 0, %s, ?, ?)',
        $row->{journalid},   $row->{jitemid},      $row->{jtalkid}, $row->{poster_id},
        $row->{date_posted}, $row->{allow_global}, _mva( $row->{bits} ),
    );
    my $ok = eval {
        $dbh->do( $sql, {}, ( $row->{title} // '' ), ( $row->{body} // '' ) );
        1;
    };
    unless ($ok) {
        $log->warn( sprintf 'insert comment journalid=%d jtalkid=%d failed: %s',
            $row->{journalid}, $row->{jtalkid}, $@ );
    }
    return $ok ? 1 : 0;
}

sub _delete_where {
    my ( $dbh, $sql ) = @_;
    my $ok = eval { $dbh->do($sql); 1 };
    $log->warn("delete failed: $sql: $@") unless $ok;
    return $ok ? 1 : 0;
}

# -----------------------------------------------------------------------------
# Full recopy: clean slate delete for the journal, then insert entries and
# (for paid accounts) comments.
# -----------------------------------------------------------------------------

sub _import_full {
    my ( $self, $u, $copy_comments ) = @_;
    my $s = $self->{stats};

    my $dbh    = _dbh();
    my $dbfrom = LJ::get_cluster_master( $u->clusterid )
        or do { $log->warn( 'cluster master not available for ' . $u->user ); return; };

    my $allow_global = $u->include_in_global_search ? 1 : 0;
    my $jid          = int $u->id;

    _delete_where( $dbh, "DELETE FROM dw1 WHERE journalid = $jid" )
        ? $s->{deletes_ok}++
        : $s->{deletes_err}++;

    # --- entries: stream row-by-row so memory stays bounded regardless of
    # journal size. mysql_use_result=1 makes DBD::mysql actually stream
    # (default is to buffer the full result set client-side). We only write
    # to $dbh (Manticore) during the loop, never back to $dbfrom, so the
    # streaming cursor's exclusive hold on $dbfrom doesn't matter.
    my %entry_bits;    # jitemid -> bits arrayref, for comment inheritance below
    my $e_sth = $dbfrom->prepare(
        q{SELECT l.jitemid, l.posterid, l.security, l.allowmask,
                 UNIX_TIMESTAMP(l.logtime) AS date_posted,
                 lt.subject, lt.event
            FROM log2 l
            JOIN logtext2 lt USING (journalid, jitemid)
            WHERE l.journalid = ?},
        { mysql_use_result => 1 },
    );
    $e_sth->execute( $u->id );
    while ( my $e = $e_sth->fetchrow_hashref ) {
        my $subject = _decode_text( \$e->{subject} );
        my $body    = _decode_text( \$e->{event} );
        my $bits    = _security_bits( $e->{security}, $e->{allowmask} );
        $entry_bits{ $e->{jitemid} } = $bits;

        my $ok = _insert_entry(
            $dbh,
            {
                journalid    => $jid,
                jitemid      => $e->{jitemid},
                poster_id    => $e->{posterid},
                date_posted  => $e->{date_posted},
                allow_global => $allow_global,
                bits         => $bits,
                title        => $subject,
                body         => $body,
            }
        );
        $ok ? $s->{entries_ok}++ : $s->{entries_err}++;
    }
    $e_sth->finish;

    return unless $copy_comments;

    # --- comments: same streaming approach, with talk2 joined to talktext2
    # so we only make one round-trip. 'D' state skipped; non-A/F states
    # forced private; A/F inherit parent entry's security from %entry_bits.
    my $c_sth = $dbfrom->prepare(
        q{SELECT t.jtalkid, t.nodeid, t.posterid, t.state,
                 UNIX_TIMESTAMP(t.datepost) AS date_posted,
                 tt.subject, tt.body
            FROM talk2 t
            JOIN talktext2 tt USING (journalid, jtalkid)
            WHERE t.journalid = ?},
        { mysql_use_result => 1 },
    );
    $c_sth->execute( $u->id );
    while ( my $c = $c_sth->fetchrow_hashref ) {
        next if $c->{state} eq 'D';

        my $subject = _decode_text( \$c->{subject} );
        my $body    = _decode_text( \$c->{body} );

        my $force_private = $c->{state} ne 'A' && $c->{state} ne 'F';
        my $bits =
            $force_private
            ? [101]
            : ( $entry_bits{ $c->{nodeid} } // [101] );

        my $ok = _insert_comment(
            $dbh,
            {
                journalid    => $jid,
                jitemid      => $c->{nodeid},
                jtalkid      => $c->{jtalkid},
                poster_id    => $c->{posterid},
                date_posted  => $c->{date_posted},
                allow_global => $allow_global,
                bits         => $bits,
                title        => $subject,
                body         => $body,
            }
        );
        $ok ? $s->{comments_ok}++ : $s->{comments_err}++;
    }
    $c_sth->finish;
}

# -----------------------------------------------------------------------------
# Single-entry upsert (also handles delete: if the entry isn't in log2
# anymore, we remove it from dw1).
# -----------------------------------------------------------------------------

sub _import_one_entry {
    my ( $self, $u, $jitemid ) = @_;
    my $s = $self->{stats};

    my $dbh    = _dbh();
    my $dbfrom = LJ::get_cluster_master( $u->clusterid ) or return;

    my $jid = int $u->id;
    my $jit = int $jitemid;

    my $row = $dbfrom->selectrow_hashref(
        q{SELECT l.posterid, l.security, l.allowmask,
                 UNIX_TIMESTAMP(l.logtime) AS date_posted,
                 lt.subject, lt.event
            FROM log2 l
            JOIN logtext2 lt USING (journalid, jitemid)
            WHERE l.journalid = ? AND l.jitemid = ?},
        undef, $u->id, $jitemid,
    );

    # Entry gone -> wipe it and any comments on it.
    unless ($row) {
        _delete_where( $dbh, "DELETE FROM dw1 WHERE journalid=$jid AND jitemid=$jit" )
            ? $s->{deletes_ok}++
            : $s->{deletes_err}++;
        return;
    }

    my $subject = _decode_text( \$row->{subject} );
    my $body    = _decode_text( \$row->{event} );
    my $bits    = _security_bits( $row->{security}, $row->{allowmask} );

    _delete_where( $dbh, "DELETE FROM dw1 WHERE journalid=$jid AND jitemid=$jit AND jtalkid=0" )
        ? $s->{deletes_ok}++
        : $s->{deletes_err}++;

    my $ok = _insert_entry(
        $dbh,
        {
            journalid    => $jid,
            jitemid      => $jit,
            poster_id    => $row->{posterid},
            date_posted  => $row->{date_posted},
            allow_global => ( $u->include_in_global_search ? 1 : 0 ),
            bits         => $bits,
            title        => $subject,
            body         => $body,
        }
    );
    $ok ? $s->{entries_ok}++ : $s->{entries_err}++;
}

# -----------------------------------------------------------------------------
# Single-comment upsert. State 'D' (or missing from talk2) -> delete.
# -----------------------------------------------------------------------------

sub _import_one_comment {
    my ( $self, $u, $jtalkid ) = @_;
    my $s = $self->{stats};

    my $dbh    = _dbh();
    my $dbfrom = LJ::get_cluster_master( $u->clusterid ) or return;

    my $jid = int $u->id;
    my $jtk = int $jtalkid;

    my $c = $dbfrom->selectrow_hashref(
        q{SELECT jtalkid, nodeid, posterid, state,
                 UNIX_TIMESTAMP(datepost) AS date_posted
            FROM talk2
            WHERE journalid = ? AND jtalkid = ?},
        undef, $u->id, $jtalkid,
    );

    if ( !$c || $c->{state} eq 'D' ) {
        _delete_where( $dbh, "DELETE FROM dw1 WHERE journalid=$jid AND jtalkid=$jtk" )
            ? $s->{deletes_ok}++
            : $s->{deletes_err}++;
        return;
    }

    my $txt = $dbfrom->selectrow_hashref(
        q{SELECT subject, body FROM talktext2 WHERE journalid = ? AND jtalkid = ?},
        undef, $u->id, $jtalkid, );
    return unless $txt;

    my $subject = _decode_text( \$txt->{subject} );
    my $body    = _decode_text( \$txt->{body} );

    # Inherit parent entry security; force private for screened/unknown states.
    my $bits;
    my $force_private = $c->{state} ne 'A' && $c->{state} ne 'F';
    if ($force_private) {
        $bits = [101];
    }
    else {
        my $parent = $dbfrom->selectrow_hashref(
            q{SELECT security, allowmask FROM log2 WHERE journalid = ? AND jitemid = ?},
            undef, $u->id, $c->{nodeid}, );
        $bits =
            $parent
            ? _security_bits( $parent->{security}, $parent->{allowmask} )
            : [101];
    }

    _delete_where( $dbh, "DELETE FROM dw1 WHERE journalid=$jid AND jtalkid=$jtk" )
        ? $s->{deletes_ok}++
        : $s->{deletes_err}++;

    my $ok = _insert_comment(
        $dbh,
        {
            journalid    => $jid,
            jitemid      => $c->{nodeid},
            jtalkid      => $jtk,
            poster_id    => $c->{posterid},
            date_posted  => $c->{date_posted},
            allow_global => ( $u->include_in_global_search ? 1 : 0 ),
            bits         => $bits,
            title        => $subject,
            body         => $body,
        }
    );
    $ok ? $s->{comments_ok}++ : $s->{comments_err}++;
}

1;
