# t/search.t
#
# End-to-end tests for the DW::Search Manticore backend. Creates a
# throwaway dw1_selftest RT table via SphinxQL, populates it with
# scenario-specific docs, and exercises DW::Search::_run_journal_query
# against it directly (the same code path the production /search handler
# takes, just pointed at a self-test table via `_table`).
#
# Doesn't touch cluster DBs or real users; doesn't exercise the
# enrichment path (that requires live Entry/Comment MySQL rows). If
# @LJ::MANTICORE isn't configured, or Manticore isn't listening on the
# configured SphinxQL port, the whole file skips.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Search;

plan skip_all => '@LJ::MANTICORE not configured'
    unless @LJ::MANTICORE;

my $dbh = DW::Search::_dbh()
    or plan skip_all => "can't connect to Manticore SphinxQL: $DBI::errstr";

my $TABLE = 'dw1_selftest';

# --- schema ---
eval { $dbh->do("DROP TABLE IF EXISTS $TABLE") };
$dbh->do(<<"EOS");
CREATE TABLE $TABLE (
    title text,
    body text,
    journalid uint,
    jitemid uint,
    jtalkid uint,
    poster_id uint,
    date_posted timestamp,
    allow_global_search bool,
    is_deleted bool,
    security_bits multi
)
EOS

END {
    if ( defined $dbh ) {
        eval { $dbh->do("DROP TABLE IF EXISTS $TABLE") };
    }
}

# --- helpers ---

sub ins {
    my %a    = @_;
    my $bits = $a{security_bits} || [102];
    my $sql  = sprintf(
        'INSERT INTO %s (journalid, jitemid, jtalkid, poster_id, date_posted,'
            . ' allow_global_search, is_deleted, security_bits, title, body)'
            . ' VALUES (%d, %d, %d, %d, %d, %d, %d, (%s), ?, ?)',
        $TABLE,
        $a{journalid}   // 999,
        $a{jitemid}     // 1,
        $a{jtalkid}     // 0,
        $a{poster_id}   // 1,
        $a{date_posted} // time(),
        defined $a{allow_global_search} ? $a{allow_global_search} : 1,
        $a{is_deleted} // 0,
        join( ',', @$bits ),
    );
    $dbh->do( $sql, {}, $a{title} // '', $a{body} // '' );
}

# Run a search via DW::Search and return a flattened list of
# "journalid/jitemid/jtalkid" keys (or [] if no matches).
sub keys_for {
    my %args = @_;
    $args{_table} = $TABLE;
    my $r = DW::Search::_run_journal_query( \%args );
    return [] unless $r && $r->{total} > 0;
    return [ map { sprintf '%d/%d/%d', $_->{journalid}, $_->{jitemid}, $_->{jtalkid} }
            @{ $r->{matches} } ];
}

# --- populate ---
# Distinct body keywords per scenario so filters can be tested in isolation.

# Security scenarios — all share the keyword 'kangaroo'.
ins(
    journalid     => 101,
    jitemid       => 1,
    security_bits => [102],
    body          => 'kangaroo eat grass in the public park'
);
ins(
    journalid     => 102,
    jitemid       => 1,
    security_bits => [101],
    body          => 'kangaroo in my secret diary'
);
ins(
    journalid           => 103,
    jitemid             => 1,
    security_bits       => [ 1, 4 ],                      # friends-only, bits 1 + 4
    allow_global_search => 0,
    body                => 'kangaroo only for friends',
);
ins(
    journalid     => 101,
    jitemid       => 2,
    is_deleted    => 1,
    security_bits => [102],
    body          => 'kangaroo post which has been deleted'
);
ins(
    journalid           => 104,
    jitemid             => 1,
    security_bits       => [102],
    allow_global_search => 0,
    body                => 'kangaroo here but globally hidden'
);

# Comment doc — same journal as jitemid=1, jtalkid>0.
ins(
    journalid     => 101,
    jitemid       => 1,
    jtalkid       => 5,
    security_bits => [102],
    body          => 'kangaroo comment on a post'
);

# Phrase-match pair.
ins(
    journalid     => 201,
    jitemid       => 1,
    security_bits => [102],
    body          => 'apples and oranges for sale at the market'
);
ins(
    journalid     => 201,
    jitemid       => 2,
    security_bits => [102],
    body          => 'apples arranged on shelves away from oranges'
);

# Sort-by-date trio.
ins(
    journalid     => 301,
    jitemid       => 1,
    date_posted   => 1000,
    security_bits => [102],
    body          => 'chronology test oldest'
);
ins(
    journalid     => 301,
    jitemid       => 2,
    date_posted   => 2000,
    security_bits => [102],
    body          => 'chronology test middle'
);
ins(
    journalid     => 301,
    jitemid       => 3,
    date_posted   => 3000,
    security_bits => [102],
    body          => 'chronology test newest'
);

# Defensive exclusion: has public bit *and* a stray 0.
ins(
    journalid     => 401,
    jitemid       => 1,
    security_bits => [ 102, 0 ],
    body          => 'penguin defensively filtered'
);

$dbh->do("FLUSH RAMCHUNK $TABLE");

# --- tests ---

subtest 'baseline: query reaches Manticore and returns matches' => sub {
    my $k = keys_for( query => 'kangaroo' );
    ok( scalar(@$k) > 0, 'kangaroo matches at least one doc' );
};

subtest 'phrase match via quoted query' => sub {
    my $k = keys_for( query => '"apples and oranges"' );
    is( scalar @$k, 1,         'exactly one phrase hit' );
    is( $k->[0],    '201/1/0', 'correct doc (journalid=201 jitemid=1)' );
};

subtest 'global search: public only, deleted/private/friends/hidden excluded' => sub {
    my $k = keys_for( query => 'kangaroo' );
    ok( ( grep  { $_ eq '101/1/0' } @$k ), 'public entry appears' );
    ok( !( grep { $_ eq '102/1/0' } @$k ), 'private entry excluded' );
    ok( !( grep { $_ eq '103/1/0' } @$k ), 'friends-only entry excluded from global' );
    ok( !( grep { $_ eq '104/1/0' } @$k ), 'allow_global_search=0 entry excluded' );
    ok( !( grep { $_ eq '101/2/0' } @$k ), 'is_deleted=1 entry excluded' );
};

subtest 'private entry hidden from secured global search' => sub {
    my $k = keys_for( query => 'secret diary' );
    is( scalar @$k, 0, 'private entry not returned' );
};

subtest 'private entry visible with ignore_security + journal scope' => sub {
    my $k = keys_for(
        query           => 'secret diary',
        userid          => 102,
        ignore_security => 1,
    );
    is( scalar @$k, 1,         'one match' );
    is( $k->[0],    '102/1/0', 'correct doc' );
};

subtest 'friends-only entry matches when caller holds a matching bit' => sub {

    # Doc has security_bits = [1, 4] (bit POSITIONS, same as bit_breakdown
    # emits). Caller with allowmask = 0b10 → bit_breakdown(2) = (1), which
    # intersects [1, 4] on position 1.
    my $k = keys_for(
        query     => 'kangaroo',
        userid    => 103,
        allowmask => 2,
    );
    is( scalar @$k, 1,         'one match' );
    is( $k->[0],    '103/1/0', 'friends-only doc returned' );
};

subtest 'friends-only entry hidden when caller lacks matching bits' => sub {

    # allowmask = 0b100 → bit_breakdown(4) = (2); no overlap with [1, 4].
    my $k = keys_for(
        query     => 'kangaroo',
        userid    => 103,
        allowmask => 4,
    );
    is( scalar @$k, 0, 'no match' );
};

subtest 'is_deleted=1 entries filtered out' => sub {
    my $k = keys_for( query => 'deleted', userid => 101 );
    is( scalar @$k, 0, 'deleted entry not returned' );
};

subtest 'allow_global_search=0 excluded from global' => sub {
    my $k = keys_for( query => 'globally hidden' );
    is( scalar @$k, 0, 'excluded from global search' );
};

subtest 'journal-scoped search confined to one journal' => sub {
    my $k = keys_for( query => 'kangaroo', userid => 101 );
    ok( scalar(@$k) > 0,             'returns matches' );
    ok( !( grep { !/^101\// } @$k ), 'all matches belong to the filtered journalid' );
};

subtest 'comments excluded by default, included when requested' => sub {
    my $without = keys_for( query => 'kangaroo comment', userid => 101 );
    ok( !( grep { !/\/0$/ } @$without ), 'default path hides comments' );

    my $with = keys_for(
        query            => 'kangaroo comment',
        userid           => 101,
        include_comments => 1,
    );
    ok( ( grep { $_ eq '101/1/5' } @$with ), 'include_comments=1 surfaces the comment doc' );
};

subtest 'sort_by date_posted' => sub {
    my $asc = keys_for(
        query   => 'chronology',
        userid  => 301,
        sort_by => 'old',
    );
    is_deeply( $asc, [ '301/1/0', '301/2/0', '301/3/0' ], 'sort_by=old yields oldest-first' );

    my $desc = keys_for(
        query   => 'chronology',
        userid  => 301,
        sort_by => 'new',
    );
    is_deeply( $desc, [ '301/3/0', '301/2/0', '301/1/0' ], 'sort_by=new yields newest-first' );
};

subtest 'defensive security_bits=0 exclusion' => sub {

    # Doc 401/1 has security_bits=[102, 0]. _journal_where emits both
    # `IN (102, ...)` and `NOT IN (0)`, so the 0 bit should shoot the doc
    # down even though its public bit would otherwise match.
    my $k = keys_for( query => 'penguin', userid => 401 );
    is( scalar @$k, 0, 'doc with stray 0 bit is excluded' );
};

subtest 'CALL SNIPPETS builds highlighted excerpts' => sub {
    my $excs = DW::Search::_snippets( $dbh, ['the quick brown kangaroo jumps over a lazy penguin'],
        $TABLE, 'kangaroo', );
    is( scalar @$excs, 1, 'one excerpt per input doc' );
    like( $excs->[0], qr/kangaroo/i, 'excerpt contains the matched keyword' );
};

done_testing();
