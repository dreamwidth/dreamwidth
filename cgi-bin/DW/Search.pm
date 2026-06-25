#!/usr/bin/perl
#
# DW::Search
#
# Single abstraction point for site-wide content search. Callers ask for
# a journal/comment search or a support search; this module runs the query
# synchronously against Manticore (SphinxQL) on @LJ::MANTICORE, or returns
# undef when search isn't configured (the caller renders a "not configured"
# error). Results use this shape:
#
#   {
#     total   => N,
#     time    => 'sec.mmm',
#     matches => [
#       # journal: { journalid, jitemid, jtalkid, poster_id, security,
#       #           subject, excerpt, url, tags, eventtime }
#       # support: { spid, type, category, subject, excerpt, url }
#     ],
#   }
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

package DW::Search;

use strict;
use v5.10;

use DBI;

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

sub enabled {
    return @LJ::MANTICORE ? 1 : 0;
}

sub search_journal {
    my %args = @_;
    return undef unless @LJ::MANTICORE;
    return _manticore_journal( \%args );
}

sub search_support {
    my %args = @_;
    return undef unless @LJ::MANTICORE;
    $args{support} = 1;
    return _manticore_support( \%args );
}

# Update the journal-level filter attributes (allow_global_search, is_deleted)
# on every one of a journal's docs, in place. Both attributes are identical
# across all of a journal's entries/comments, so account-level changes — the
# global-search opt-out, account suspend/delete/undelete — only need to flip
# the attribute. Manticore's RT index supports UPDATE-by-attribute, so this is
# a single cheap columnar write, not a recopy.
#
# Integers are interpolated, not bound: Manticore's SphinxQL types every '?'
# placeholder as a string and rejects string values against uint attributes.
# Column names come from a fixed whitelist and values are forced through %d, so
# there is no injection surface.
sub set_journal_flag {
    my ( $journalid, %flags ) = @_;
    return 0 unless @LJ::MANTICORE;

    $journalid = int $journalid;
    return 0 unless $journalid;

    my @sets;
    for my $col (qw/ allow_global_search is_deleted /) {
        next unless exists $flags{$col};
        push @sets, sprintf '%s = %d', $col, ( $flags{$col} ? 1 : 0 );
    }
    return 0 unless @sets;

    my $dbh = _dbh() or return 0;
    $dbh->do( sprintf 'UPDATE dw1 SET %s WHERE journalid = %d', join( ', ', @sets ), $journalid );
    return $dbh->err ? 0 : 1;
}

# ---------------------------------------------------------------------------
# Manticore backend — synchronous SphinxQL
# ---------------------------------------------------------------------------

sub _dbh {
    my ( $host, undef, $sql_port ) = @LJ::MANTICORE;
    my $dbh = DBI->connect(
        "DBI:mysql:host=$host;port=$sql_port",
        undef, undef,
        {
            RaiseError => 0,
            AutoCommit => 1,
            PrintError => 0,
        },
    ) or return undef;
    $dbh->do(q{SET NAMES 'utf8'});
    return $dbh->err ? undef : $dbh;
}

sub _manticore_journal {
    my $args = shift;

    # Open one Manticore connection and reuse it for the query, the excerpt
    # SNIPPETS calls, and SHOW META, instead of reconnecting in each helper.
    $args->{_dbh} //= _dbh() or return undef;
    my $raw = _run_journal_query($args) or return undef;
    return _enrich_journal( $args, $raw );
}

sub _manticore_support {
    my $args = shift;
    $args->{_dbh} //= _dbh() or return undef;
    my $raw = _run_support_query($args) or return undef;
    return _enrich_support( $args, $raw );
}

# Raw entry/comment query against Manticore. Returns {total, time, matches}
# with matches keyed by (journalid, jitemid, jtalkid, poster_id, date_posted)
# — no MySQL loads yet, no excerpts. Exposed via `_table` so tests can point
# at a throwaway self-test table instead of the production dw1.
sub _run_journal_query {
    my $args = shift;
    my $dbh  = $args->{_dbh} // _dbh() or return undef;

    my $tbl    = $args->{_table} // 'dw1';
    my $offset = $args->{offset} || 0;
    my $limit  = $args->{_limit} // 20;

    my ( $where, @where_binds ) = _journal_where($args);
    my $order = _journal_order($args);

    my $sql =
          "SELECT id, journalid, jitemid, jtalkid, poster_id, date_posted "
        . "FROM $tbl WHERE MATCH(?) $where $order "
        . "LIMIT ?, ? OPTION max_query_time=15000";

    my $start = time;
    my $rows  = $dbh->selectall_arrayref(
        $sql,
        { Slice => {} },
        _match_expr( $args->{query} ),
        @where_binds, $offset, $limit,
    );
    return undef if $dbh->err;

    return _result( $dbh, $rows, $start );
}

sub _run_support_query {
    my $args = shift;
    my $dbh  = $args->{_dbh} // _dbh() or return undef;

    my $tbl    = $args->{_table} // 'dwsupport';
    my $offset = $args->{offset} || 0;
    my $limit  = $args->{_limit} // 20;

    my $sql =
          "SELECT id, spid, poster_id, faqid, touchtime FROM $tbl "
        . "WHERE MATCH(?) ORDER BY touchtime DESC "
        . "LIMIT ?, ? OPTION max_query_time=15000";

    my $start = time;
    my $rows  = $dbh->selectall_arrayref(
        $sql,
        { Slice => {} },
        _match_expr( $args->{query} ),
        $offset, $limit,
    );
    return undef if $dbh->err;

    # Old worker keyed the supportlog MySQL lookup off $match->{doc};
    # alias id -> doc so enrichment doesn't care which backend produced the row.
    $_->{doc} = $_->{id} for @$rows;

    return _result( $dbh, $rows, $start );
}

sub _result {
    my ( $dbh, $rows, $start ) = @_;
    my $meta  = $dbh->selectall_hashref( 'SHOW META', 'Variable_name' );
    my $total = $meta->{total_found} ? $meta->{total_found}{Value} + 0 : scalar @$rows;
    return {
        total   => $total,
        time    => sprintf( '%.03f', ( time - $start ) ),
        matches => $rows,
    };
}

sub _journal_where {
    my $args = shift;
    my ( @c, @b );

    push @c, 'is_deleted = 0';

    if ( $args->{userid} ) {
        push @c, 'journalid = ?';
        push @b, $args->{userid};
    }
    else {
        push @c, 'allow_global_search = 1';
    }

    push @c, 'jtalkid = 0' unless $args->{include_comments};

    unless ( $args->{ignore_security} ) {

        # Manticore rejects MVA filters passed as bind params (they get typed
        # as 'stringlist' and the MVA side errors out), so interpolate the
        # integers directly. Safe because bit_breakdown only returns ints.
        my @bits = ( 102, LJ::bit_breakdown( $args->{allowmask} ) );
        push @c, 'security_bits IN (' . join( ',', map { int $_ } @bits ) . ')';

        # Defensive exclude: drop any rows with a stray 0 security bit.
        push @c, 'security_bits NOT IN (0)';
    }

    return ( 'AND ' . join( ' AND ', @c ), @b );
}

sub _journal_order {
    my $args = shift;
    my $sb   = $args->{sort_by} // '';
    return 'ORDER BY date_posted DESC' if $sb eq 'new';
    return 'ORDER BY date_posted ASC'  if $sb eq 'old';
    return '';    # relevance (default)
}

# Strip a single matching pair of outer quotes (the user's "phrase intent")
# and re-wrap with SphinxQL phrase syntax.
sub _match_expr {
    my $q = shift // '';
    return qq{"$1"} if $q =~ /^['"](.+)['"]$/;
    return $q;
}

# ---------------------------------------------------------------------------
# Enrichment — MySQL reload + visibility recheck + excerpts
# ---------------------------------------------------------------------------

# Prime the caches that _enrich_journal's per-match loop reads, so a page of
# matches costs a handful of bulk queries instead of one MySQL round trip per
# match. This only warms caches against the same singletons the loop builds; a
# miss here just falls back to an individual load, so it can never change which
# results are shown -- only how many queries it takes to show them.
sub _preload_journal_matches {
    my $matches = shift;
    return unless $matches && @$matches;

    # Journal + poster user objects, multi-loaded once. The loop and the
    # results template both call load_userid on these ids; warming them here
    # turns 2N point lookups into a single multi-get.
    LJ::load_userids( grep { $_ } map { $_->{journalid}, $_->{poster_id} } @$matches );

    my ( @entries, @comments );
    for my $m (@$matches) {
        if ( $m->{jtalkid} == 0 ) {
            push @entries, LJ::Entry->new( $m->{journalid}, jitemid => $m->{jitemid} );
        }
        else {
            push @comments, LJ::Comment->new( $m->{journalid}, jtalkid => $m->{jtalkid} );
        }
    }

    # Comments: rows load across journals in a single call; their text and the
    # parent entries they pull in for visibility checks are warmed per journal.
    if (@comments) {
        LJ::Comment->preload_rows;

        my %txt_by_jid;
        push @{ $txt_by_jid{ $_->journalid } }, $_->jtalkid for @comments;
        for my $jid ( keys %txt_by_jid ) {
            my $ju = LJ::load_userid($jid) or next;
            LJ::get_talktext2( $ju, @{ $txt_by_jid{$jid} } );
        }

        push @entries, grep { $_ } map { $_->entry } @comments;
    }

    # Entries (top-level matches plus comment parents): the entry bulk loaders
    # are single-journal, so group by journalid first.
    my %ent_by_jid;
    push @{ $ent_by_jid{ $_->journalid } }, $_ for @entries;
    for my $jid ( keys %ent_by_jid ) {
        LJ::Entry->preload_rows( $ent_by_jid{$jid} );
        my $ju = LJ::load_userid($jid) or next;
        LJ::get_logtext2( $ju, map { $_->jitemid } @{ $ent_by_jid{$jid} } );
    }
}

sub _enrich_journal {
    my ( $args, $res ) = @_;
    return $res if $res->{total} <= 0;

    my $query  = $args->{query};
    my $tbl    = $args->{_table} // 'dw1';
    my $remote = LJ::load_userid( $args->{remoteid} );
    my $dbh    = $args->{_dbh} // _dbh() or return $res;

    # Warm row/text/user caches for the whole page up front so the loop below
    # reads them without a per-match MySQL round trip.
    _preload_journal_matches( $res->{matches} );

    my @out;
    for my $match ( @{ $res->{matches} } ) {

        if ( $match->{jtalkid} == 0 ) {
            my $entry = LJ::Entry->new( $match->{journalid}, jitemid => $match->{jitemid}, );

            # The index can't represent everything visible_to() decides: its
            # security_bits are viewer-agnostic and frozen at index time, and
            # things like a suspended poster/journal or adult-content gating
            # live only in MySQL. The copier is also async and best-effort, so
            # a since-deleted row can briefly survive. Re-check against MySQL
            # and drop anything we can't show rather than rendering a "deleted
            # or unavailable" placeholder row.
            next unless $entry && $entry->valid && $entry->visible_to($remote);

            $match->{entry} = $entry->event_text;
            $match->{entry} =~ s#<(?:br|p)\s*/?># #gi;
            $match->{entry} = LJ::strip_html( $match->{entry} );
            $match->{entry} ||= '(this entry only contains html content)';

            $match->{subject}  = $entry->subject_text || '(no subject)';
            $match->{url}      = $entry->url;
            $match->{tags}     = $entry->tag_map;
            $match->{security} = $entry->security;
            $match->{security} = 'access'
                if $match->{security} eq 'usemask'
                && $entry->allowmask == 1;
            $match->{eventtime} = $entry->eventtime_mysql;
            push @out, $match;
        }
        else {
            my $cmt   = LJ::Comment->new( $match->{journalid}, jtalkid => $match->{jtalkid}, );
            my $entry = $cmt->entry;

            # Same as above, and more so for comments: deleting a single
            # comment doesn't notify the copier at all, so a deleted comment
            # lingers in the index until its entry is next recopied. Skip
            # comments (or comments whose entry has gone away) that we can no
            # longer show, instead of emitting a placeholder row.
            next
                unless $entry
                && $entry->valid
                && $entry->visible_to($remote)
                && $cmt
                && $cmt->valid
                && $cmt->visible_to($remote);

            $match->{entry} = $cmt->body_text;
            $match->{entry} ||= '(this comment only contains html content)';

            $match->{subject}  = $cmt->subject_text || '(no subject)';
            $match->{url}      = $cmt->url;
            $match->{security} = $entry->security;
            $match->{security} = 'access'
                if $match->{security} eq 'usemask'
                && $entry->allowmask == 1;
            $match->{eventtime} = $cmt->{datepost};
            push @out, $match;
        }
    }

    # Drop the filtered-out matches from the result set; @out now holds only
    # the entries/comments we were able to load and are allowed to show.
    $res->{matches} = \@out;

    my $body_exc = _snippets( $dbh, [ map { $_->{entry} } @out ],   $tbl, $query );
    my $subj_exc = _snippets( $dbh, [ map { $_->{subject} } @out ], $tbl, $query );

    if ( @$body_exc == @out ) {
        for my $m (@out) {
            delete $m->{entry};
            $m->{excerpt} = shift @$body_exc;
            $m->{subject} = shift @$subj_exc if @$subj_exc;
        }
    }
    else {

        # Excerpt count mismatch means something went sideways in the
        # SNIPPETS call; users still see their matches, just without
        # the highlighted snippet.
        for my $m (@out) {
            delete $m->{entry};
            $m->{excerpt} = '(something terrible happened to the excerpts)';
        }
    }

    return $res;
}

sub _enrich_support {
    my ( $args, $res ) = @_;
    return $res if $res->{total} <= 0;

    my $query    = $args->{query};
    my $remoteid = $args->{remoteid};
    my $tbl      = $args->{_table} // 'dwsupport';

    my $dbr    = LJ::get_db_reader()        or return $res;
    my $remote = LJ::load_userid($remoteid) or return $res;

    my @out;
    my %spcache;
    for my $match ( @{ $res->{matches} } ) {
        my ( $spid, $type, $content ) =
            $dbr->selectrow_array( q{SELECT spid, type, message FROM supportlog WHERE splid = ?},
            undef, $match->{doc}, );
        next if $dbr->err;

        my $sp = ( $spcache{$spid} ||= LJ::Support::load_request($spid) )
            or next;

        my $visible = LJ::Support::can_read_cat( $sp->{_cat}, $remote );
        if ( $type eq 'internal' ) {
            $visible = LJ::Support::can_read_internal( $sp, $remote );
        }
        elsif ( $type eq 'screened' ) {
            $visible = LJ::Support::can_read_screened( $sp, $remote );
        }
        next unless $visible;

        # supportlog messages are stored as raw HTML. Strip it for readability
        # before excerpting (turn breaks into spaces, drop tags). This is
        # cosmetic only -- _snippets entity-escapes whatever survives before it
        # reaches the page. Mirrors the journal entry path in _enrich_journal.
        $content =~ s#<(?:br|p)\s*/?># #gi;
        $content = LJ::strip_html($content);
        $content ||= '(this support entry only contains html content)';

        $match->{url}  = "$LJ::SITEROOT/support/see_request?id=$spid";
        $match->{type} = $type;
        $match->{spid} = $spid;

        # category and subject are likewise printed unfiltered by the
        # template; entity-escape them here since neither is run through
        # SNIPPETS (the subject is operator-uncontrolled request text).
        $match->{category} = LJ::ehtml( $sp->{_cat}->{catname} );
        $match->{subject}  = LJ::ehtml( $sp->{subject} );
        $match->{content}  = $content;
        push @out, $match;
    }

    my $dbh  = $args->{_dbh} // _dbh() or return $res;
    my $excs = _snippets( $dbh, [ map { $_->{content} } @out ], $tbl, $query );

    if ( @$excs == @out ) {
        for my $m (@out) {
            delete $m->{content};
            $m->{excerpt} = shift @$excs;
        }
    }
    else {
        for my $m (@out) {
            delete $m->{content};
            $m->{excerpt} = '(something terrible happened to the excerpts)';
        }
    }

    $res->{matches} = [ grep { exists $_->{excerpt} } @out ];
    return $res;
}

# One CALL SNIPPETS for the whole page. Manticore accepts a list literal for
# the data argument and returns a row per document, so we collapse what used to
# be a round trip per doc (40+ for a full page, serialized against a remote
# Manticore) into a single call. The placeholder list expands to
# ('doc1','doc2',...) client-side before it reaches the server.
#
# SNIPPETS echoes its input back verbatim apart from wrapping query matches in
# <b> highlight tags, and the results templates print the excerpt unfiltered.
# So this is the single security boundary: entity-escape each text here, before
# SNIPPETS runs, leaving only SNIPPETS' own <b> tags as live markup in the
# output. Callers must therefore pass plain text (strip_html alone is not
# enough -- its regex leaves orphaned '<', '>', and '<!--' comment openers,
# any of which would otherwise inject raw HTML into the page).
#
# On any error we return [], which the callers treat as an excerpt-count
# mismatch and degrade to a placeholder rather than dropping matches.
sub _snippets {
    my ( $dbh, $texts, $tbl, $query ) = @_;
    return [] unless @$texts;

    my $list = join ',', ('?') x @$texts;
    my $rows = $dbh->selectall_arrayref(
        "CALL SNIPPETS(($list), ?, ?)",
        undef, ( map { LJ::ehtml( $_ // '' ) } @$texts ),
        $tbl, $query,
    );
    return [] if $dbh->err || !$rows;

    return [ map { $_->[0] // '' } @$rows ];
}

1;
