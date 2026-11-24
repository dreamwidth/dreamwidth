# t/change-poster-id.t
#
# Test DW::Task::ChangePosterId and DW::Worker::ChangePosterId reparenting
# of talkleft, talkleft_xfp, and talkleftct memcache across same-cluster,
# cross-cluster, batched, retry, and failure paths.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
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
use Test::MockObject;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user with_fake_memcache );
use DW::Locker;
use DW::Task::ChangePosterId;
use DW::Worker::ChangePosterId;
BEGIN { require "$ENV{LJHOME}/bin/maint/clean_caches.pl"; }

my @xfp_cleanup_uids;

END {
    if (@xfp_cleanup_uids) {
        if ( my $dbh = LJ::get_db_writer() ) {
            my $placeholders = join( ',', ('?') x @xfp_cleanup_uids );
            $dbh->do( "DELETE FROM talkleft_xfp WHERE userid IN ($placeholders)",
                undef, @xfp_cleanup_uids );
        }
    }
}

sub talkleft_rows {
    my ( $cid, $uid ) = @_;
    my $dbcm = LJ::get_cluster_master($cid)
        or die "Unable to connect to cluster $cid";
    my $rows = $dbcm->selectall_arrayref(
        'SELECT posttime, journalid, nodetype, nodeid, jtalkid, publicitem '
            . 'FROM talkleft WHERE userid = ? '
            . 'ORDER BY posttime, journalid, nodeid, jtalkid',
        undef, $uid
    );
    die $dbcm->errstr if $dbcm->err;
    return $rows;
}

subtest 'same-cluster reparenting updates talkleft and invalidates talkleftct' => sub {
    with_fake_memcache {
        my $fu    = temp_user( cluster => 1 );
        my $tu    = temp_user( cluster => 1 );
        my $other = temp_user( cluster => 1 );
        my $ju    = temp_user( cluster => 2 );

        my $pub_entry  = $ju->t_post_fake_entry;
        my $priv_entry = $ju->t_post_fake_entry( security => 'friends' );

        my $c1 = $pub_entry->t_enter_comment( u => $fu );
        my $c2 = $priv_entry->t_enter_comment( u => $fu );
        my $c3 = $pub_entry->t_enter_comment( u => $tu );
        my $c4 = $pub_entry->t_enter_comment( u => $other );

        my $fu_before    = talkleft_rows( 1, $fu->id );
        my $tu_before    = talkleft_rows( 1, $tu->id );
        my $other_before = talkleft_rows( 1, $other->id );

        is( scalar @$fu_before, 2, 'from user starts with 2 talkleft rows' );
        is( scalar @$tu_before, 1, 'to user starts with 1 talkleft row' );

        # Warm talkleftct memcache before running the worker.
        is( $fu->num_comments_posted, 2, 'from user cached count starts at 2' );
        is( $tu->num_comments_posted, 1, 'to user cached count starts at 1' );

        my $task =
            DW::Task::ChangePosterId->new( { from_userid => $fu->id, to_userid => $tu->id } );
        is( $task->work('test-same-cluster'), DW::Task::COMPLETED, 'task completes' );

        my $fu_after    = talkleft_rows( 1, $fu->id );
        my $tu_after    = talkleft_rows( 1, $tu->id );
        my $other_after = talkleft_rows( 1, $other->id );

        is( scalar @$fu_after, 0, 'from user has 0 talkleft rows after reparenting' );
        is( scalar @$tu_after, 3, 'to user has all 3 talkleft rows after reparenting' );

        my @expected = sort {
                   $a->[0] <=> $b->[0]
                || $a->[1] <=> $b->[1]
                || $a->[3] <=> $b->[3]
                || $a->[4] <=> $b->[4]
        } ( @$fu_before, @$tu_before );
        is_deeply( $tu_after, \@expected,
            'moved talkleft rows preserve all columns including publicitem' );
        is_deeply( $other_after, $other_before, 'unrelated user talkleft rows untouched' );

        is( LJ::MemCache::get( [ $fu->id, "talkleftct:" . $fu->id ] ),
            undef, 'from user talkleftct cache was invalidated' );
        is( LJ::MemCache::get( [ $tu->id, "talkleftct:" . $tu->id ] ),
            undef, 'to user talkleftct cache was invalidated' );

        is( $fu->num_comments_posted, 0, 'from user num_comments_posted is now 0' );
        is( $tu->num_comments_posted, 3, 'to user num_comments_posted is now 3' );
    };
};

subtest 'cross-cluster reparenting moves talkleft to target cluster' => sub {
    with_fake_memcache {
        my $fu    = temp_user( cluster => 1 );
        my $tu    = temp_user( cluster => 2 );
        my $other = temp_user( cluster => 1 );
        my $ju1   = temp_user( cluster => 1 );
        my $ju2   = temp_user( cluster => 2 );

        my $pub_entry  = $ju1->t_post_fake_entry;
        my $priv_entry = $ju2->t_post_fake_entry( security => 'friends' );

        $pub_entry->t_enter_comment( u => $fu );
        $priv_entry->t_enter_comment( u => $fu );
        $pub_entry->t_enter_comment( u => $tu );
        $pub_entry->t_enter_comment( u => $other );

        my $fu_before    = talkleft_rows( 1, $fu->id );
        my $tu_before    = talkleft_rows( 2, $tu->id );
        my $other_before = talkleft_rows( 1, $other->id );

        is( scalar @$fu_before,       2, 'from user starts with 2 talkleft rows on cluster 1' );
        is( scalar @$tu_before,       1, 'to user starts with 1 talkleft row on cluster 2' );
        is( $fu->num_comments_posted, 2, 'from user cached count starts at 2' );
        is( $tu->num_comments_posted, 1, 'to user cached count starts at 1' );

        my $task =
            DW::Task::ChangePosterId->new( { from_userid => $fu->id, to_userid => $tu->id } );
        is( $task->work('test-cross-cluster'), DW::Task::COMPLETED, 'task completes' );

        is( scalar @{ talkleft_rows( 1, $fu->id ) },
            0, 'from user has 0 talkleft rows left on cluster 1' );
        is( scalar @{ talkleft_rows( 1, $tu->id ) },
            0, 'to user has no stranded talkleft rows on cluster 1' );

        my $tu_after = talkleft_rows( 2, $tu->id );
        my @expected = sort {
                   $a->[0] <=> $b->[0]
                || $a->[1] <=> $b->[1]
                || $a->[3] <=> $b->[3]
                || $a->[4] <=> $b->[4]
        } ( @$fu_before, @$tu_before );
        is_deeply( $tu_after, \@expected,
            'to user has all 3 talkleft rows on cluster 2 with columns preserved' );
        is_deeply( talkleft_rows( 1, $other->id ),
            $other_before, 'unrelated user talkleft rows on cluster 1 untouched' );

        is( $fu->num_comments_posted, 0, 'from user num_comments_posted is now 0' );
        is( $tu->num_comments_posted, 3, 'to user num_comments_posted is now 3' );
    };
};

subtest 'cross-cluster retry does not duplicate already-copied talkleft rows' => sub {
    with_fake_memcache {
        my $fu = temp_user( cluster => 1 );
        my $tu = temp_user( cluster => 2 );
        my $ju = temp_user( cluster => 1 );

        my $entry = $ju->t_post_fake_entry;
        $entry->t_enter_comment( u => $fu );

        my $fu_rows = talkleft_rows( 1, $fu->id );
        is( scalar @$fu_rows, 1, 'from user has 1 talkleft row' );

        # Simulate a prior attempt that inserted into cluster 2 before crashing
        # prior to deleting from cluster 1.
        my $to_dbcm = LJ::get_cluster_master(2);
        $to_dbcm->do(
'INSERT INTO talkleft (userid, posttime, journalid, nodetype, nodeid, jtalkid, publicitem) '
                . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
            undef, $tu->id, @{ $fu_rows->[0] }
        );
        die $to_dbcm->errstr if $to_dbcm->err;

        my $task =
            DW::Task::ChangePosterId->new( { from_userid => $fu->id, to_userid => $tu->id } );
        is( $task->work('test-cross-cluster-retry'), DW::Task::COMPLETED, 'retry completes' );

        is( scalar @{ talkleft_rows( 1, $fu->id ) }, 0, 'source row deleted on retry' );
        is_deeply( talkleft_rows( 2, $tu->id ), $fu_rows, 'target row not duplicated on retry' );
    };
};

subtest 'batching moves more than 100 talkleft rows (same-cluster and cross-cluster)' => sub {
    for my $case ( [ 'same-cluster', 1, 1 ], [ 'cross-cluster', 1, 2 ] ) {
        my ( $label, $from_cid, $to_cid ) = @$case;
        subtest $label => sub {
            with_fake_memcache {
                my $fu = temp_user( cluster => $from_cid );
                my $tu = temp_user( cluster => $to_cid );

                my $from_dbcm = LJ::get_cluster_master($from_cid);
                my $base_time = time() - 500;
                for my $i ( 1 .. 105 ) {
                    my $pub = ( $i % 2 ) ? '1' : '0';
                    $from_dbcm->do(
                        'INSERT INTO talkleft '
                            . '(userid, posttime, journalid, nodetype, nodeid, jtalkid, publicitem) '
                            . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
                        undef, $fu->id, $base_time + $i, $fu->id, 'L', 1000 + $i, $i, $pub
                    );
                    die $from_dbcm->errstr if $from_dbcm->err;
                }

                my $before = talkleft_rows( $from_cid, $fu->id );
                is( scalar @$before, 105, 'seeded 105 talkleft rows' );

                my $task = DW::Task::ChangePosterId->new(
                    { from_userid => $fu->id, to_userid => $tu->id } );
                is( $task->work("test-batch-$label"), DW::Task::COMPLETED, 'task completes' );

                is( scalar @{ talkleft_rows( $from_cid, $fu->id ) },
                    0, 'all 105 rows removed from source user' );
                is_deeply( talkleft_rows( $to_cid, $tu->id ),
                    $before, 'all 105 rows present on target user cluster' );
            };
        };
    }
};

subtest 'talkleft_xfp staging rows are updated to target user' => sub {
    with_fake_memcache {
        my $fu    = temp_user( cluster => 1 );
        my $tu    = temp_user( cluster => 2 );
        my $other = temp_user( cluster => 1 );
        push @xfp_cleanup_uids, $fu->id, $tu->id, $other->id;

        my $dbh = LJ::get_db_writer();
        my $now = time();
        $dbh->do(
            'INSERT INTO talkleft_xfp '
                . '(userid, posttime, journalid, nodetype, nodeid, jtalkid, publicitem) '
                . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
            undef, $fu->id, $now, $other->id, 'L', 42, 7, '1'
        );
        die $dbh->errstr if $dbh->err;
        $dbh->do(
            'INSERT INTO talkleft_xfp '
                . '(userid, posttime, journalid, nodetype, nodeid, jtalkid, publicitem) '
                . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
            undef, $other->id, $now, $other->id, 'L', 42, 8, '0'
        );
        die $dbh->errstr if $dbh->err;

        my $task =
            DW::Task::ChangePosterId->new( { from_userid => $fu->id, to_userid => $tu->id } );
        is( $task->work('test-xfp'), DW::Task::COMPLETED, 'task completes' );

        my $fu_ct = $dbh->selectrow_array( 'SELECT COUNT(*) FROM talkleft_xfp WHERE userid = ?',
            undef, $fu->id );
        my $tu_ct = $dbh->selectrow_array( 'SELECT COUNT(*) FROM talkleft_xfp WHERE userid = ?',
            undef, $tu->id );
        my $other_ct = $dbh->selectrow_array( 'SELECT COUNT(*) FROM talkleft_xfp WHERE userid = ?',
            undef, $other->id );

        is( $fu_ct,    0, 'from user has 0 rows left in talkleft_xfp' );
        is( $tu_ct,    1, 'to user has 1 row in talkleft_xfp' );
        is( $other_ct, 1, 'unrelated user row in talkleft_xfp untouched' );
    };
};

subtest 'unavailable target cluster fails cleanly without losing source talkleft rows' => sub {
    with_fake_memcache {
        my $fu = temp_user( cluster => 1 );
        my $tu = temp_user( cluster => 2 );
        my $ju = temp_user( cluster => 1 );

        my $entry = $ju->t_post_fake_entry;
        $entry->t_enter_comment( u => $fu );

        my $before = talkleft_rows( 1, $fu->id );
        is( scalar @$before, 1, 'from user has 1 talkleft row before failure' );

        # Allow cluster loop to succeed, then fail connecting to target cluster 2
        # inside fix_talkleft.
        my $orig     = \&LJ::get_cluster_master;
        my $c2_calls = 0;
        my $res;
        {
            no warnings qw( redefine once );
            local *LJ::get_cluster_master = sub {
                my ($arg) = @_;
                my $cid = LJ::isu($arg) ? $arg->clusterid : $arg;
                if ( $cid == 2 && ++$c2_calls > 1 ) {
                    return undef;
                }
                return $orig->(@_);
            };

            my $task =
                DW::Task::ChangePosterId->new( { from_userid => $fu->id, to_userid => $tu->id } );
            $res = $task->work('test-cluster-down');
        }

        is( $res, DW::Task::FAILED, 'task returns FAILED when target cluster is unavailable' );
        is_deeply( talkleft_rows( 1, $fu->id ),
            $before, 'source talkleft row preserved on failure' );
    };
};

subtest 'legacy DW::Worker::ChangePosterId updates talkleft consistently' => sub {
    with_fake_memcache {
        my $fu = temp_user( cluster => 1 );
        my $tu = temp_user( cluster => 2 );
        my $ju = temp_user( cluster => 1 );

        my $entry = $ju->t_post_fake_entry;
        $entry->t_enter_comment( u => $fu );

        my $fu_before = talkleft_rows( 1, $fu->id );
        is( $fu->num_comments_posted, 1, 'from user cached count starts at 1' );
        is( $tu->num_comments_posted, 0, 'to user cached count starts at 0' );

        my ( $completed, $failed ) = ( 0, '' );
        my $job = Test::MockObject->new;
        $job->mock( arg => sub { { from_userid => $fu->id, to_userid => $tu->id } } );
        $job->mock( completed         => sub { $completed = 1 } );
        $job->mock( failed            => sub { $failed    = $_[1]; return } );
        $job->mock( permanent_failure => sub { $failed    = $_[1]; return } );

        DW::Worker::ChangePosterId->work($job);

        is( $failed,    '', 'legacy worker did not fail' );
        is( $completed, 1,  'legacy worker completed' );
        is( scalar @{ talkleft_rows( 1, $fu->id ) }, 0, 'legacy worker cleared source talkleft' );
        is_deeply( talkleft_rows( 2, $tu->id ),
            $fu_before, 'legacy worker moved talkleft to target cluster' );
        is( $fu->num_comments_posted, 0, 'legacy worker updated from user count' );
        is( $tu->num_comments_posted, 1, 'legacy worker updated to user count' );
    };
};

for my $implementation (qw(task worker)) {
    subtest "$implementation coordinates the talkleft_xfp handoff" => sub {
        with_fake_memcache {
            my $fu = temp_user( cluster => 1 );
            my $tu = temp_user( cluster => 2 );
            push @xfp_cleanup_uids, $fu->id, $tu->id;

            my $dbh = LJ::get_db_writer();
            my @row = ( time(), $fu->id, 'L', 42, 7, '1' );
            $dbh->do(
                'INSERT INTO talkleft_xfp '
                    . '(userid, posttime, journalid, nodetype, nodeid, jtalkid, publicitem) '
                    . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
                undef, $fu->id, @row
            ) or die $dbh->errstr;

            my $staging_owners = sub {
                my $owners = $dbh->selectcol_arrayref(
                    'SELECT userid FROM talkleft_xfp WHERE userid IN (?, ?) ORDER BY userid',
                    undef, $fu->id, $tu->id )
                    or die $dbh->errstr;
                return $owners;
            };
            my $run_migration = sub {
                my ($expect_success) = @_;
                my $args = { from_userid => $fu->id, to_userid => $tu->id };
                if ( $implementation eq 'task' ) {
                    my $task     = DW::Task::ChangePosterId->new($args);
                    my $expected = $expect_success ? DW::Task::COMPLETED : DW::Task::FAILED;
                    is( $task->work('test-xfp-lock'),
                        $expected, 'task reports the expected status' );
                }
                else {
                    my ( $completed, $failed ) = ( 0, '' );
                    my $job = Test::MockObject->new;
                    $job->mock( arg       => sub { $args } );
                    $job->mock( completed => sub { $completed = 1 } );
                    $job->mock( failed    => sub { $failed = $_[1]; return } );
                    $job->mock(
                        permanent_failure => sub { fail('worker reported permanent failure') } );
                    DW::Worker::ChangePosterId->work($job);
                    is( $completed, $expect_success, 'worker completes only with the lock free' );

                    if ($expect_success) {
                        is( $failed, '', 'worker retry did not fail' );
                    }
                    else {
                        like( $failed, qr/talkleft_xfp/,
                            'worker reports a retryable lock failure' );
                    }
                }
            };

            my $lock = DW::Locker->new->trylock( 'talkleft_xfp', class => 'talkleft_xfp' )
                or BAIL_OUT("Could not acquire test lock: $DW::Locker::Error");
            $run_migration->(0);
            is_deeply(
                $staging_owners->(),
                [ $fu->id ],
                'migration leaves staging untouched while locked'
            );
            clean_caches_talkleft_xfp( $dbh, 0 );
            is_deeply(
                $staging_owners->(),
                [ $fu->id ],
                'cleaner leaves staging untouched while locked'
            );
            is_deeply( talkleft_rows( 1, $fu->id ), [], 'cleaner has not copied the source row' );
            is_deeply( talkleft_rows( 2, $tu->id ), [], 'neither actor copied a target row' );
            $lock->release;

            if ( $implementation eq 'task' ) {
                clean_caches_talkleft_xfp( $dbh, 0 );
                is_deeply( talkleft_rows( 1, $fu->id ),
                    [ \@row ], 'cleaner drains to source before migration' );
                $run_migration->(1);
            }
            else {
                $run_migration->(1);
                is_deeply(
                    $staging_owners->(),
                    [ $tu->id ],
                    'migration repoints staging before drain'
                );
            }
            clean_caches_talkleft_xfp( $dbh, 0 );
            is_deeply( $staging_owners->(), [], 'cleaner removes the drained staging row' );
            is_deeply( talkleft_rows( 1, $fu->id ), [], 'no row remains under the old owner' );
            is_deeply( talkleft_rows( 2, $tu->id ),
                [ \@row ], 'exactly one row reaches the new owner' );
        };
    };
}

done_testing();
