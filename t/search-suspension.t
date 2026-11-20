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

done_testing();
