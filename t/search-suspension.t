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
use LJ::Test qw(temp_user with_fake_memcache);

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

my $indexed_deleted_flag = sub {
    my ( $journalid, $jitemid, $jtalkid ) = @_;
    my ($flag) = $dbh->selectrow_array(
        sprintf 'SELECT is_deleted FROM dw1 WHERE journalid = %d AND jitemid = %d AND jtalkid = %d',
        $journalid, $jitemid, $jtalkid );
    BAIL_OUT( $dbh->errstr ) if $dbh->err;
    return defined $flag ? 0 + $flag : undef;
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

# Race 4: second transition between reconciliation read and Manticore UPDATE
# (active -> suspended before insert -> unsuspended before reconciliation UPDATE)
my $untouched = $journal->t_post_fake_entry( body => "$query untouched" );
isnt( $untouched->jitemid, $entry->jitemid, 'untouched entry is distinct from copied entry' );
DW::Task::SearchCopier::copy_entry( $journal, $untouched->jitemid, 1 );
my $index_flags = sub {
    return [
        $indexed_deleted_flag->( $journal->id, $entry->jitemid,     0 ),
        $indexed_deleted_flag->( $journal->id, $untouched->jitemid, 0 ),
        $indexed_deleted_flag->( $journal->id, $entry->jitemid,     $comment->jtalkid ),
        $indexed_deleted_flag->( $viewer->id,  $control->jitemid,   0 ),
    ];
};
{
    my $orig_uncompress = \&LJ::text_uncompress;
    my $orig_update     = \&DW::Task::SearchCopier::_update_deleted_flag;
    my ( $did_suspend, $did_unsuspend ) = ( 0, 0 );
    my @flags_after_updates;
    no warnings 'redefine';
    local *LJ::text_uncompress = sub {
        if ( !$did_suspend++ ) {
            $journal->set_suspended( $viewer, 'race4 suspend before insert' );
        }
        return $orig_uncompress->(@_);
    };
    local *DW::Task::SearchCopier::_update_deleted_flag = sub {
        if ( !$did_unsuspend++ ) {
            $journal->set_unsuspended( $viewer, 'race4 unsuspend before reconcile update' );
        }
        $orig_update->(@_);
        push @flags_after_updates, $index_flags->();
    };
    DW::Task::SearchCopier::copy_entry( $journal, $entry->jitemid, 1 );
    is_deeply(
        \@flags_after_updates,
        [ [ 1, 0, 0, 0 ], [ 0, 0, 0, 0 ] ],
        'race4 temporarily hides only the just-copied entry'
    );
}
{
    my $result = DW::Search::search_journal(
        remoteid         => $viewer->id,
        query            => $query,
        include_comments => 1,
    ) or BAIL_OUT('race4 search failed');
    is( $result->{total}, 4, 'after transition during reconciliation UPDATE: search total' );
    is_deeply(
        [ sort map { $_->{url} } @{ $result->{matches} } ],
        [ sort( $control->url, $entry->url, $untouched->url, $comment->url ) ],
        'after transition during reconciliation UPDATE: both copied and untouched entries visible'
    );
}

# Race 5: reverse transition during reconciliation UPDATE
# (suspended -> unsuspended before insert -> re-suspended before reconciliation UPDATE)
ok( $journal->set_suspended( $viewer, 'race5 initial suspend' ), 'suspend for race5' );
{
    my $orig_uncompress = \&LJ::text_uncompress;
    my $orig_update     = \&DW::Task::SearchCopier::_update_deleted_flag;
    my ( $did_unsuspend, $did_resuspend ) = ( 0, 0 );
    my @flags_after_updates;
    no warnings 'redefine';
    local *LJ::text_uncompress = sub {
        if ( !$did_unsuspend++ ) {
            $journal->set_unsuspended( $viewer, 'race5 unsuspend before insert' );
        }
        return $orig_uncompress->(@_);
    };
    local *DW::Task::SearchCopier::_update_deleted_flag = sub {
        if ( !$did_resuspend++ ) {
            $journal->set_suspended( $viewer, 'race5 resuspend before reconcile update' );
        }
        $orig_update->(@_);
        push @flags_after_updates, $index_flags->();
    };
    DW::Task::SearchCopier::copy_entry( $journal, $entry->jitemid, 1 );
    is_deeply(
        \@flags_after_updates,
        [ [ 0, 1, 1, 0 ], [ 1, 1, 1, 0 ] ],
        'race5 temporarily unhides only the just-copied entry'
    );
}
$check_search->( 'after reverse transition during reconciliation UPDATE', 0 );
ok( $journal->set_unsuspended( $viewer, 'cleanup after race5' ), 'unsuspend after race5' );

# Remove extra untouched entry before remaining status checks
$dbh->do( sprintf 'DELETE FROM dw1 WHERE journalid = %d AND jitemid = %d AND jtalkid = 0',
    $journal->id, $untouched->jitemid );
LJ::delete_entry( $journal, $untouched->jitemid, undef, $untouched->anum );

with_fake_memcache {
    my $task         = DW::Task::SearchCopier->new( { userid => $journal->id } );
    my $throttle_key = [ $journal->id, 'search-copy-full:' . $journal->id ];
    {
        my $orig_uncompress = \&LJ::text_uncompress;
        my $suspended       = 0;
        no warnings 'redefine';
        local *LJ::text_uncompress = sub {
            unless ( $suspended++ ) {
                ok( $journal->set_suspended( $viewer, 'suspend before full-copy insert' ),
                    'suspend during unforced full copy' );
            }
            return $orig_uncompress->(@_);
        };
        local *DW::Task::SearchCopier::_update_deleted_flag = sub {
            die "Injected reconciliation failure\n";
        };
        eval { $task->work };
        like(
            $@,
            qr/Injected reconciliation failure/,
            'unforced full copy raises on repair failure'
        );
    }
    is( $indexed_deleted_flag->( $journal->id, $entry->jitemid, 0 ),
        0, 'failed reconciliation leaves the inserted entry with a stale flag' );
    ok( !LJ::MemCache::get($throttle_key), 'failed full copy does not set the throttle' );
    is( $task->work, DW::Task::COMPLETED, 'unforced full-copy retry completes' );
    $check_search->( 'after retry of failed full-copy reconciliation', 0 );
    ok( LJ::MemCache::get($throttle_key), 'successful full-copy retry sets the throttle' );
    ok( $journal->set_unsuspended( $viewer, 'cleanup after full-copy retry' ),
        'unsuspend after full-copy retry' );
};

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
