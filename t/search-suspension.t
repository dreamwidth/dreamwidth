# t/search-suspension.t
#
# Check that search excludes suspended journals during recopy and rebuild.
# Requires a configured Manticore test instance with a dw1 journal table.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use DW::Task::SearchCopier;
use LJ::Test qw(temp_user);

plan skip_all => '@LJ::MANTICORE not configured' unless @LJ::MANTICORE;

my $dbh = DW::Search::_dbh()
    or plan skip_all => "can't connect to Manticore SphinxQL: $DBI::errstr";
$dbh->do('SELECT id FROM dw1 LIMIT 1');
plan skip_all => 'dw1 test table not initialized' if $dbh->err;

my @indexed_journals;

END {
    foreach my $journalid (@indexed_journals) {
        $dbh->do( sprintf 'DELETE FROM dw1 WHERE journalid = %d', $journalid )
            or warn "Failed to clean up Manticore test journal $journalid: " . $dbh->errstr;
    }
}

my $journal = temp_user();
my $viewer  = temp_user();
push @indexed_journals, $journal->id, $viewer->id;
my $query = sprintf 'searchsuspension%d', $journal->id;

$journal->set_prop( { opt_blockglobalsearch => 'N', not_approved => 0 } );
$viewer->set_prop(  { opt_blockglobalsearch => 'N', not_approved => 0 } );
my $entry   = $journal->t_post_fake_entry( body => $query );
my $comment = $entry->t_enter_comment( u => $viewer, body => $query );
my $control = $viewer->t_post_fake_entry( body => $query );

my $recopy = sub {
    DW::Task::SearchCopier::copy_entry( $journal, undef, 1 );
    DW::Task::SearchCopier::copy_comment( $journal, $comment->jtalkid );
};

my $check_search = sub {
    my ( $label, $visible ) = @_;
    my @urls = ( $control->url );
    push @urls, $entry->url, $comment->url if $visible;
    my $result = DW::Search::search_journal(
        remoteid         => $viewer->id,
        query            => $query,
        include_comments => 1,
    ) or BAIL_OUT("$label: search failed");
    is( $result->{total}, scalar @urls, "$label: search total" );
    is_deeply(
        [ sort map { $_->{url} } @{ $result->{matches} } ],
        [ sort @urls ],
        "$label: search hits"
    );
};

DW::Task::SearchCopier::copy_entry( $viewer, $control->jitemid, 1 );
$recopy->();
$check_search->( 'before suspension', 1 );

ok( $journal->set_suspended( $viewer, 'search suspension test' ), 'suspend journal' );
$check_search->( 'after suspension', 0 );
$recopy->();
$check_search->( 'after recopy while suspended', 0 );

$dbh->do( sprintf 'DELETE FROM dw1 WHERE journalid = %d', $journal->id )
    or BAIL_OUT( 'Could not clear the test journal from dw1: ' . $dbh->errstr );
$recopy->();
$check_search->( 'after rebuild while suspended', 0 );

ok( $journal->set_unsuspended( $viewer, 'search suspension test' ), 'unsuspend journal' );
$check_search->( 'after unsuspension without recopy', 1 );

# Race 1: stale suspended user object passed after journal is unsuspended
ok( $journal->set_suspended( $viewer, 'stale handle test' ), 'suspend for stale handle test' );
my $stale_suspended = bless {%$journal}, ref $journal;
ok( $journal->set_unsuspended( $viewer, 'stale handle test' ),
    'unsuspend before stale-handle recopy' );
DW::Task::SearchCopier::copy_entry( $stale_suspended, $entry->jitemid, 1 );
DW::Task::SearchCopier::copy_comment( $stale_suspended, $comment->jtalkid );
$check_search->( 'after recopy with stale suspended user handle', 1 );

# Race 2: unsuspension completes while copy_entry / copy_comment is mid-flight
ok( $journal->set_suspended( $viewer, 'mid-flight unsuspend entry' ),
    'suspend for mid-flight entry unsuspend race' );
{
    my $orig  = \&LJ::text_uncompress;
    my $fired = 0;
    no warnings 'redefine';
    local *LJ::text_uncompress = sub {
        if ( !$fired++ ) {
            $journal->set_unsuspended( $viewer, 'mid-flight unsuspend entry' );
        }
        return $orig->(@_);
    };
    DW::Task::SearchCopier::copy_entry( $journal, $entry->jitemid, 1 );
}
$check_search->( 'after mid-flight unsuspension during copy_entry', 1 );

ok( $journal->set_suspended( $viewer, 'mid-flight unsuspend comment' ),
    'suspend for mid-flight comment unsuspend race' );
{
    my $orig  = \&LJ::text_uncompress;
    my $fired = 0;
    no warnings 'redefine';
    local *LJ::text_uncompress = sub {
        if ( !$fired++ ) {
            $journal->set_unsuspended( $viewer, 'mid-flight unsuspend comment' );
        }
        return $orig->(@_);
    };
    DW::Task::SearchCopier::copy_comment( $journal, $comment->jtalkid );
}
$check_search->( 'after mid-flight unsuspension during copy_comment', 1 );

# Race 3: suspension completes while copy_entry is mid-flight
{
    my $orig  = \&LJ::text_uncompress;
    my $fired = 0;
    no warnings 'redefine';
    local *LJ::text_uncompress = sub {
        if ( !$fired++ ) {
            $journal->set_suspended( $viewer, 'mid-flight suspend entry' );
        }
        return $orig->(@_);
    };
    DW::Task::SearchCopier::copy_entry( $journal, $entry->jitemid, 1 );
}
$check_search->( 'after mid-flight suspension during copy_entry', 0 );
ok( $journal->set_unsuspended( $viewer, 'cleanup after mid-flight suspend' ),
    'unsuspend after mid-flight suspend race' );

# Status split: deleted is inactive (hidden), undeleted and memorial remain visible
ok( $journal->set_deleted, 'delete journal' );
$recopy->();
$check_search->( 'after recopy while deleted', 0 );
ok( $journal->set_visible, 'undelete journal' );
$check_search->( 'after undelete without recopy', 1 );

ok( $journal->set_memorial, 'mark journal memorial' );
$recopy->();
$check_search->( 'after recopy while memorial', 1 );

done_testing();
