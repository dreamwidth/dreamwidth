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
    my $raw  = _run_journal_query($args) or return undef;
    return _enrich_journal( $args, $raw );
}

sub _manticore_support {
    my $args = shift;
    my $raw  = _run_support_query($args) or return undef;
    return _enrich_support( $args, $raw );
}

# Raw entry/comment query against Manticore. Returns {total, time, matches}
# with matches keyed by (journalid, jitemid, jtalkid, poster_id, date_posted)
# — no MySQL loads yet, no excerpts. Exposed via `_table` so tests can point
# at a throwaway self-test table instead of the production dw1.
sub _run_journal_query {
    my $args = shift;
    my $dbh  = _dbh() or return undef;

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
    my $dbh  = _dbh() or return undef;

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

sub _enrich_journal {
    my ( $args, $res ) = @_;
    return $res if $res->{total} <= 0;

    my $query    = $args->{query};
    my $remoteid = $args->{remoteid};
    my $tbl      = $args->{_table} // 'dw1';

    my @out;
    for my $match ( @{ $res->{matches} } ) {
        my $remote = LJ::load_userid($remoteid);

        if ( $match->{jtalkid} == 0 ) {
            my $entry = LJ::Entry->new( $match->{journalid}, jitemid => $match->{jitemid}, );
            if ( $entry && $entry->valid && $entry->visible_to($remote) ) {
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
            }
            else {
                $match->{entry} =
                    '(sorry, this entry has been deleted or is otherwise unavailable)';
                $match->{subject} = 'Entry deleted or unavailable.';
            }
            push @out, $match;
        }
        else {
            my $cmt   = LJ::Comment->new( $match->{journalid}, jtalkid => $match->{jtalkid}, );
            my $entry = $cmt->entry;
            if (   $entry
                && $entry->valid
                && $entry->visible_to($remote)
                && $cmt
                && $cmt->valid
                && $cmt->visible_to($remote) )
            {
                $match->{entry} = $cmt->body_text;
                $match->{entry} ||= '(this comment only contains html content)';

                $match->{subject}  = $cmt->subject_text || '(no subject)';
                $match->{url}      = $cmt->url;
                $match->{security} = $entry->security;
                $match->{security} = 'access'
                    if $match->{security} eq 'usemask'
                    && $entry->allowmask == 1;
                $match->{eventtime} = $cmt->{datepost};
            }
            else {
                $match->{entry} =
                    '(sorry, this comment has been deleted or is otherwise unavailable)';
                $match->{subject} = 'Comment deleted or unavailable.';
            }
            push @out, $match;
        }
    }

    my $dbh      = _dbh() or return $res;
    my $body_exc = _snippets( $dbh, [ map { $_->{entry} } @out ], $tbl, $query );
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

    my $dbh  = _dbh() or return $res;
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

# One CALL SNIPPETS per doc. Per-call latency is ~1ms on localhost and we
# cap at 20 matches per page, so a tuple literal buys us nothing but
# prepared-statement quoting pain.
#
# SNIPPETS echoes its input back verbatim apart from wrapping query matches in
# <b> highlight tags, and the results templates print the excerpt unfiltered.
# So this is the single security boundary: entity-escape the text here, before
# SNIPPETS runs, leaving only SNIPPETS' own <b> tags as live markup in the
# output. Callers must therefore pass plain text (strip_html alone is not
# enough -- its regex leaves orphaned '<', '>', and '<!--' comment openers,
# any of which would otherwise inject raw HTML into the page).
sub _snippets {
    my ( $dbh, $texts, $tbl, $query ) = @_;
    my @out;
    for my $t (@$texts) {
        my ($exc) = $dbh->selectrow_array(
            'CALL SNIPPETS(?, ?, ?)',
            undef, LJ::ehtml( $t // '' ),
            $tbl, $query,
        );
        push @out, ( $exc // '' );
    }
    return \@out;
}

1;
