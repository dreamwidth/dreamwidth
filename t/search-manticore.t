# t/search-manticore.t
#
# End-to-end smoke test for Sphinx::Search library against Manticore.
#
# Validates that the read path of sphinx-search-gm will work when
# retargeted at @LJ::MANTICORE: Sphinx::Search's binary protocol is
# accepted on Manticore port 3312, filter semantics match what we
# expect, security_bits MVA logic produces the right result sets,
# BuildExcerpts works, and sort orders work.
#
# Doesn't touch cluster DBs or real users. Creates a throwaway RT
# table in Manticore via SphinxQL CREATE TABLE, populates it with a
# curated set of docs covering each test scenario, runs queries, and
# drops the table at end.
#
# Skipped entirely if @LJ::MANTICORE isn't configured (so CI without
# a Manticore instance won't fail).
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

use DBI;
use Sphinx::Search;

plan skip_all => '@LJ::MANTICORE not configured'
    unless @LJ::MANTICORE;

my ( $host, $sphinx_port, $sql_port ) = @LJ::MANTICORE;
my $test_table = 'dw1_selftest';

# --- setup: throwaway RT table via SphinxQL ---

my $dbh = DBI->connect(
    "DBI:mysql:host=$host;port=$sql_port",
    undef, undef,
    {
        RaiseError        => 1,
        PrintError        => 0,
        AutoCommit        => 1,
        mysql_enable_utf8 => 1,
    },
);
plan skip_all => "can't connect to Manticore SphinxQL at $host:$sql_port: $DBI::errstr"
    unless $dbh;

eval { $dbh->do("DROP TABLE IF EXISTS $test_table") };
$dbh->do(<<"EOS");
CREATE TABLE $test_table (
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

# Drop the test table even if tests die midway.
END {
    if ( defined $dbh ) {
        eval { $dbh->do("DROP TABLE IF EXISTS $test_table") };
    }
}

# --- helpers ---

# Insert one doc with named args. Defaults for every field so tests only
# have to set what they care about.
sub ins {
    my %a    = @_;
    my $bits = $a{security_bits} || [102];    # public by default
    my $sql  = sprintf(
        'INSERT INTO %s (journalid, jitemid, jtalkid, poster_id, date_posted,'
            . ' allow_global_search, is_deleted, security_bits, title, body)'
            . ' VALUES (%d, %d, %d, %d, %d, %d, %d, (%s), ?, ?)',
        $test_table,
        $a{journalid}   // 999,
        $a{jitemid}     // 1,
        $a{jtalkid}     // 0,
        $a{poster_id}   // 1,
        $a{date_posted} // time(),
        defined $a{allow_global_search} ? $a{allow_global_search} : 1,
        $a{is_deleted}  // 0,
        join( ',', @$bits ),
    );
    $dbh->do( $sql, {}, $a{title} // '', $a{body} // '' );
}

# Fresh Sphinx::Search configured the way sphinx-search-gm does.
sub _sx {
    my $sx = Sphinx::Search->new;
    $sx->SetServer( $host, $sphinx_port );
    $sx->SetMatchMode(SPH_MATCH_ALL);
    $sx->SetSortMode(SPH_SORT_RELEVANCE);
    $sx->SetMaxQueryTime(15_000);
    $sx->SetLimits( 0, 100 );
    return $sx;
}

# Extract the set of (journalid, jitemid, jtalkid) tuples from a result.
sub _keys_of {
    my $r = shift;
    return [] unless ref $r eq 'HASH' && $r->{total} && $r->{total} > 0;
    return [
        map { sprintf '%d/%d/%d', $_->{journalid}, $_->{jitemid}, $_->{jtalkid} }
            @{ $r->{matches} }
    ];
}

# --- populate ---
# Distinct body keywords per scenario so filters can be tested in isolation.

# Security scenarios — all use the keyword 'kangaroo' so one query covers them.
ins(
    journalid => 101, jitemid => 1,
    security_bits => [102],
    title         => 'Public hello',
    body          => 'kangaroos eat grass in the public park'
);
ins(
    journalid => 102, jitemid => 1,
    security_bits => [101],
    title         => 'Private hello',
    body          => 'kangaroos in my secret diary'
);
ins(
    journalid           => 103, jitemid => 1,
    security_bits       => [ 1, 4 ],                  # friends-only, bits 1 + 4
    allow_global_search => 0,
    title               => 'Friends hello',
    body                => 'kangaroos only for friends',
);
ins(
    journalid => 101, jitemid => 2,
    is_deleted    => 1,
    security_bits => [102],
    body          => 'kangaroo post which has been deleted'
);
ins(
    journalid           => 104, jitemid => 1,
    security_bits       => [102],
    allow_global_search => 0,                         # opted out of global
    body                => 'kangaroos here but globally hidden'
);

# Comment doc — same journal as jitemid=1, with jtalkid>0
ins(
    journalid => 101, jitemid => 1, jtalkid => 5,
    security_bits => [102],
    body          => 'kangaroo comment on a post'
);

# Phrase-match pair — distinct keyword set
ins(
    journalid => 201, jitemid => 1,
    security_bits => [102],
    body          => 'apples and oranges for sale at the market'
);
ins(
    journalid => 201, jitemid => 2,
    security_bits => [102],
    body          => 'apples arranged on shelves away from oranges'
);

# Sort-by-date trio — predictable ordering, separate keyword
ins(
    journalid => 301, jitemid => 1,
    date_posted   => 1000,
    security_bits => [102],
    body          => 'chronology test oldest'
);
ins(
    journalid => 301, jitemid => 2,
    date_posted   => 2000,
    security_bits => [102],
    body          => 'chronology test middle'
);
ins(
    journalid => 301, jitemid => 3,
    date_posted   => 3000,
    security_bits => [102],
    body          => 'chronology test newest'
);

# Malformed-bit doc to exercise the `SetFilter('security_bits', [0], 1)`
# exclusion that sphinx-search-gm applies defensively.
ins(
    journalid => 401, jitemid => 1,
    security_bits => [ 102, 0 ],                      # has public bit *and* a stray 0
    body          => 'penguin defensively filtered'
);

$dbh->do("FLUSH RAMCHUNK $test_table");

# --- tests ---

# 1. Baseline: does Sphinx::Search talk to Manticore at all?
{
    my $sx = _sx();
    my $r  = $sx->Query( 'kangaroo', $test_table );
    ok( $r && $r->{total} && $r->{total} > 0,
        '1. Sphinx::Search Query returns matches from Manticore' );
}

# 2. Phrase match via SPH_MATCH_PHRASE
{
    my $sx = _sx();
    $sx->SetMatchMode(SPH_MATCH_PHRASE);
    my $r = $sx->Query( 'apples and oranges', $test_table );
    my $k = _keys_of($r);
    is( scalar @$k, 1, '2. phrase match: exactly one doc' );
    is( $k->[0], '201/1/0', '2. phrase match: correct doc (journalid=201 jitemid=1)' );
}

# 3. Public entry visible globally (no journalid filter, security_bits=[102])
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted',          [0] );
    $sx->SetFilter( 'allow_global_search', [1] );
    $sx->SetFilter( 'security_bits',       [102] );
    $sx->SetFilter( 'security_bits',       [0], 1 );    # defensive exclude
    my $r = $sx->Query( 'kangaroo', $test_table );
    my $k = _keys_of($r);
    ok( ( grep { $_ eq '101/1/0' } @$k ),
        '3. public entry appears in global search' );
    ok( !( grep { $_ eq '102/1/0' } @$k ),
        '3. private entry (journalid=102) excluded' );
    ok( !( grep { $_ eq '103/1/0' } @$k ),
        '3. friends-only entry (journalid=103) excluded from global' );
    ok( !( grep { $_ eq '104/1/0' } @$k ),
        '3. allow_global_search=0 entry (journalid=104) excluded' );
    ok( !( grep { $_ eq '101/2/0' } @$k ), '3. is_deleted=1 entry excluded' );
}

# 4. Private entry hidden from global (no ignore_security)
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted',          [0] );
    $sx->SetFilter( 'allow_global_search', [1] );
    $sx->SetFilter( 'security_bits',       [102] );
    $sx->SetFilter( 'security_bits',       [0], 1 );
    my $r = $sx->Query( 'secret diary', $test_table );
    is( $r->{total} || 0, 0, '4. private entry NOT returned in secured search' );
}

# 5. Private entry visible with ignore_security (no security filter)
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted', [0] );

    # journal-scoped so we only look at the private journal
    $sx->SetFilter( 'journalid', [102] );
    my $r = $sx->Query( 'secret diary', $test_table );
    my $k = _keys_of($r);
    is( scalar @$k, 1, '5. private entry IS returned when ignore_security' );
    is( $k->[0], '102/1/0', '5. ignore_security returns the right doc' );
}

# 6. Friends-only entry matches when caller holds any of its bits
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted', [0] );
    $sx->SetFilter( 'journalid',  [103] );

    # caller has bit 1 set (so bit_breakdown gives [1]). Include public (102)
    # and the caller's bits. Exclude defensive 0.
    $sx->SetFilter( 'security_bits', [ 102, 1 ] );
    $sx->SetFilter( 'security_bits', [0], 1 );
    my $r = $sx->Query( 'kangaroo', $test_table );
    my $k = _keys_of($r);
    is( scalar @$k, 1, '6. friends-only with matching bit: 1 match' );
    is( $k->[0], '103/1/0', '6. friends-only matching bit returns the doc' );
}

# 7. Friends-only entry does NOT match when caller lacks the bits
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted', [0] );
    $sx->SetFilter( 'journalid',  [103] );

    # caller has bit 2 (allowmask=0b010 -> bit_breakdown = [2]). Doc has [1,4].
    $sx->SetFilter( 'security_bits', [ 102, 2 ] );
    $sx->SetFilter( 'security_bits', [0], 1 );
    my $r = $sx->Query( 'kangaroo', $test_table );
    is( $r->{total} || 0, 0, '7. friends-only with non-matching bit: no match' );
}

# 8. is_deleted filter
{
    my $sx = _sx();
    $sx->SetFilter( 'journalid',  [101] );
    $sx->SetFilter( 'is_deleted', [0] );
    my $r = $sx->Query( 'deleted', $test_table );
    is( $r->{total} || 0, 0, '8. is_deleted=1 entry filtered out' );
}

# 9. allow_global_search=0 excluded from global
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted',          [0] );
    $sx->SetFilter( 'allow_global_search', [1] );
    my $r = $sx->Query( 'globally hidden', $test_table );
    is( $r->{total} || 0, 0,
        '9. allow_global_search=0 entry excluded from global search' );
}

# 10. Journal-scoped search
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted', [0] );
    $sx->SetFilter( 'journalid',  [101] );
    my $r = $sx->Query( 'kangaroo', $test_table );
    my $k = _keys_of($r);
    ok( scalar(@$k) > 0, '10. journal-scoped search returns matches' );
    ok( !( grep { !/^101\// } @$k ),
        '10. all matches belong to the filtered journalid' );
}

# 11. Comments excluded when jtalkid range 0..0
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted', [0] );
    $sx->SetFilter( 'journalid',  [101] );
    $sx->SetFilterRange( 'jtalkid', 0, 0 );
    my $r = $sx->Query( 'kangaroo', $test_table );
    my $k = _keys_of($r);
    ok( !( grep { !/\/0$/ } @$k ),
        '11. with jtalkid range 0..0: no comments in results' );
}

# 12. Comments included when no jtalkid filter
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted', [0] );
    $sx->SetFilter( 'journalid',  [101] );
    my $r = $sx->Query( 'kangaroo comment', $test_table );
    my $k = _keys_of($r);
    ok( ( grep { $_ eq '101/1/5' } @$k ),
        '12. comment doc appears when include_comments path is used' );
}

# 13. Sort by date_posted — ascending and descending
{
    my $sx = _sx();
    $sx->SetFilter( 'journalid', [301] );
    $sx->SetSortMode( SPH_SORT_ATTR_ASC, 'date_posted' );
    my $asc = _keys_of( $sx->Query( 'chronology', $test_table ) );
    is_deeply(
        $asc,
        [ '301/1/0', '301/2/0', '301/3/0' ],
        '13a. sort ASC by date_posted returns oldest-first'
    );

    my $sx2 = _sx();
    $sx2->SetFilter( 'journalid', [301] );
    $sx2->SetSortMode( SPH_SORT_ATTR_DESC, 'date_posted' );
    my $desc = _keys_of( $sx2->Query( 'chronology', $test_table ) );
    is_deeply(
        $desc,
        [ '301/3/0', '301/2/0', '301/1/0' ],
        '13b. sort DESC by date_posted returns newest-first'
    );
}

# 14. BuildExcerpts returns highlighted keyword snippets
{
    my $sx       = _sx();
    my $excerpts = $sx->BuildExcerpts(
        ['the quick brown kangaroo jumps'],
        $test_table,
        'kangaroo', {}
    );
    ok( $excerpts && ref $excerpts eq 'ARRAY' && @$excerpts,
        '14. BuildExcerpts returns an arrayref with content' );
    like( $excerpts->[0] || '',
        qr/kangaroo/i, '14. excerpt contains the matched keyword' );
}

# 15. Defensive security_bits=[0] exclusion
# Doc 401/1 has security_bits=[102, 0]. Without the exclusion filter it would
# match a [102]-only caller. WITH the exclusion, Manticore should reject it
# because one of its MVA values is 0.
{
    my $sx = _sx();
    $sx->SetFilter( 'is_deleted',     [0] );
    $sx->SetFilter( 'journalid',      [401] );
    $sx->SetFilter( 'security_bits',  [102] );
    my $without_exclude = $sx->Query( 'penguin', $test_table );
    ok( $without_exclude && $without_exclude->{total} > 0,
        '15a. malformed doc matches without the defensive exclusion' );

    my $sx2 = _sx();
    $sx2->SetFilter( 'is_deleted',    [0] );
    $sx2->SetFilter( 'journalid',     [401] );
    $sx2->SetFilter( 'security_bits', [102] );
    $sx2->SetFilter( 'security_bits', [0], 1 );    # the defensive exclude
    my $with_exclude = $sx2->Query( 'penguin', $test_table );
    is( ( $with_exclude->{total} || 0 ),
        0, '15b. defensive exclude filter rejects malformed doc' );
}

done_testing();
