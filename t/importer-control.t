# t/importer-control.t
#
# Tests cancelling an import and rerunning its items: which items and jobs change, which
# are left alone, and that nothing is changed when the import is not in a state to retry.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );
use TheSchwartz::Job;

use DW::Importer::Control;
use DW::Importer::Queue;
use DW::Importer::Registry;

my $reg = 'DW::Importer::Registry';

# a source with items that depend on each other like a real one:
#   a <- b <- c, a <- d, and e on its own
{

    package Test::Control::Worker;
    use base 'DW::Importer::Job';
    sub run { }

    package Test::Control::A;
    use base 'Test::Control::Worker';

    package Test::Control::B;
    use base 'Test::Control::Worker';

    package Test::Control::C;
    use base 'Test::Control::Worker';

    package Test::Control::D;
    use base 'Test::Control::Worker';

    package Test::Control::E;
    use base 'Test::Control::Worker';
}

$reg->register_source( name => 'ctltest', kind => 'file', enabled => sub { 1 } );
my %deps   = ( a => [], b => ['a'], c => ['b'], d => ['a'], e => [] );
my $typeid = 9410;
foreach my $name (qw( a b c d e )) {
    $reg->register_item(
        name       => "ct_$name",
        source     => 'ctltest',
        class      => 'Test::Control::' . uc $name,
        typeid     => $typeid++,
        depends_on => [ map { "ct_$_" } @{ $deps{$name} } ],
    );
}
END { $reg->unregister_source('ctltest') }

my $actor = temp_user();

# an import of $u in the given statuses: ( a => 'failed', ... )
sub setup {
    my ( $u, $id, %status ) = @_;
    my $dbh = LJ::get_db_writer();
    $dbh->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5, options) '
            . 'VALUES (?, ?, ?, ?, ?, ?)',
        undef, $u->id, $id, 'remote.example', 'someone', 'x', Storable::nfreeze( {} )
    );
    foreach my $name ( keys %status ) {
        $dbh->do(
            'INSERT INTO import_items (userid, item, status, created, last_touch, import_data_id, '
                . 'priority) VALUES (?, ?, ?, UNIX_TIMESTAMP(), 0, ?, 0)',
            undef, $u->id, "ct_$name", $status{$name}, $id
        );
    }
}

sub statuses {
    my ( $u, $id ) = @_;
    $id //= 1;
    my $rows =
        LJ::get_db_writer()
        ->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $id );
    return { map { my $n = $_->[0]; $n =~ s/^ct_//; $n => $_->[1] } @$rows };
}

# a job for the item, as the scheduler makes it; grabbed_until is in the future for a job a
# worker is running
sub add_job {
    my ( $u, $name, %opts ) = @_;
    my $job = TheSchwartz::Job->new(
        funcname => 'Test::Control::' . uc $name,
        uniqkey  => "ct_$name-" . $u->id,
        arg      => { userid => $u->id, import_data_id => $opts{import_data_id} // 1 },
    );
    my $handle = LJ::theschwartz()->insert($job) or die "could not add a job";

    if ( $opts{running} ) {
        DW::Importer::Queue->each_dbh(
            sub {
                $_[0]->do(
                    'UPDATE job SET grabbed_until = ? WHERE jobid = ?',
                    undef, time() + 3600,
                    $handle->jobid
                );
            }
        );
    }
}

sub job_items {
    my ( $u, $id ) = @_;
    my ($jobs) = DW::Importer::Queue->jobs_for_import( $u, $id // 1 );
    return join ',', sort keys %$jobs;
}

# The statushistory table can't be written with every MySQL setting the tests run under (its
# shdate has no default), so what would be recorded is captured instead.
my @history;
{
    no warnings 'redefine';
    *LJ::statushistory_add = sub { push @history, [@_]; return 1 };
}

sub history {
    my ( $u, $type ) = @_;
    return [ map { $_->[3] } grep { $_->[0] == $u->id && $_->[2] eq $type } @history ];
}

# cancel: unfinished items are aborted, finished ones are not, and only jobs nobody is
# running are removed
{
    my $u = temp_user();
    setup( $u, 1, a => 'succeeded', b => 'queued', c => 'init', d => 'ready', e => 'failed' );
    add_job( $u, 'b' );
    add_job( $u, 'd', running => 1 );

    my $res = DW::Importer::Control->cancel( $u, 1, actor => $actor );

    is_deeply( $res->{aborted}, [qw( ct_b ct_c ct_d )], 'the unfinished items were aborted' );
    is_deeply(
        statuses($u),
        { a => 'succeeded', b => 'aborted', c => 'aborted', d => 'aborted', e => 'failed' },
        'finished items were left as they were'
    );
    is( $res->{jobs_removed}, 1,      'the job nobody was running was removed' );
    is( $res->{jobs_running}, 1,      'and the running one was counted' );
    is( job_items($u),        'ct_d', 'and left in the queue to finish' );
    ok( $res->{queue_complete}, 'the whole queue was read' );

    my $notes = history( $u, 'import_cancel' );
    is( scalar @$notes, 1, 'the cancel is in the status history' );
    is( ( grep { $_->[1] == $actor->id } @history ) ? 1 : 0,
        1, 'under the administrator who did it' );
    like( $notes->[0], qr/import 1: aborted 3 items/, 'with what it did' );

    is( DW::Importer::Control->cancel( $u, 1, actor => $actor )->{aborted}->[0],
        undef, 'cancelling again changes nothing' );
}

# cancel only touches the import it was asked about
{
    my $u = temp_user();
    setup( $u, 1, a => 'queued' );
    setup( $u, 2, a => 'queued', e => 'ready' );
    add_job( $u, 'e', import_data_id => 2 );

    DW::Importer::Control->cancel( $u, 1, actor => $actor );
    is( statuses( $u, 1 )->{a}, 'aborted', 'the import cancelled is aborted' );
    is_deeply(
        statuses( $u, 2 ),
        { a => 'queued', e => 'ready' },
        'a later import of the same user is untouched'
    );
    is( job_items( $u, 2 ), 'ct_e', 'and so is its job' );
}

# retry: only the user's latest import, and only when nothing is in flight; a refusal
# changes nothing
{
    my $u = temp_user();
    setup( $u, 1, a => 'failed', b => 'aborted' );
    setup( $u, 2, a => 'succeeded' );
    is_deeply(
        DW::Importer::Control->retry( $u, 1, actor => $actor ),
        { error => 'notlatest' },
        'an older import is not retried'
    );
    is_deeply( statuses($u), { a => 'failed', b => 'aborted' }, 'and not changed' );

    my $v = temp_user();
    setup( $v, 1, a => 'failed', b => 'aborted', c => 'queued', e => 'ready' );
    is_deeply(
        DW::Importer::Control->retry( $v, 1, actor => $actor ),
        { error => 'inflight' },
        'an import with items ready or queued is not retried'
    );
    is_deeply(
        statuses($v),
        { a => 'failed', b => 'aborted', c => 'queued', e => 'ready' },
        'and not changed'
    );

    my $w = temp_user();
    setup( $w, 1, a => 'failed', b => 'aborted' );
    add_job( $w, 'a', running => 1 );
    is_deeply(
        DW::Importer::Control->retry( $w, 1, actor => $actor ),
        { error => 'jobsexist' },
        'a job still in the queue (a cancelled one that is still running) blocks it'
    );
    is_deeply( statuses($w), { a => 'failed', b => 'aborted' }, 'and nothing is changed' );

    my $x = temp_user();
    setup( $x, 1, a => 'succeeded', b => 'succeeded' );
    is_deeply(
        DW::Importer::Control->retry( $x, 1, actor => $actor ),
        { error => 'nothing' },
        'with nothing failed there is nothing to retry'
    );
    is_deeply(
        DW::Importer::Control->retry( $x, 1, actor => $actor, items => ['ct_nonesuch'] ),
        { error => 'nothing' },
        'and an item that is not part of the import is ignored'
    );
}

# retry resets what failed along with what was aborted behind it, and only readies the
# items whose dependencies have succeeded
{
    my $u = temp_user();
    setup(
        $u, 1,
        a => 'succeeded',
        b => 'failed',
        c => 'aborted',
        d => 'succeeded',
        e => 'failed'
    );

    my $res = DW::Importer::Control->retry( $u, 1, actor => $actor );
    is_deeply( $res->{reset},   [qw( ct_b ct_c ct_e )], 'failed and aborted items were reset' );
    is_deeply( $res->{ready},   [qw( ct_b ct_e )],      'those that can run now are ready' );
    is_deeply( $res->{waiting}, [qw( ct_c )],           'one is waiting for the one before it' );
    is_deeply(
        statuses($u),
        { a => 'succeeded', b => 'ready', c => 'init', d => 'succeeded', e => 'ready' },
        'the statuses are what the scheduler expects'
    );
    is( scalar @{ history( $u, 'import_retry' ) }, 1, 'the retry is in the status history' );

    # and when b has succeeded again, c is released as for any import
    DW::Importer::Items->advance( $u, 1, 'ct_b', 'success' );
    is( statuses($u)->{c},
        'ready', 'the item that waited is released when its dependency succeeds' );
}

# naming an item reruns it in any finished state, taking what was aborted behind it
{
    my $u = temp_user();
    setup( $u, 1, a => 'failed', b => 'aborted', c => 'aborted', d => 'aborted', e => 'failed' );
    my $res = DW::Importer::Control->retry( $u, 1, actor => $actor, items => ['ct_a'] );
    is_deeply(
        $res->{reset},
        [qw( ct_a ct_b ct_c ct_d )],
        'what depended on it, however indirectly, is reset'
    );
    is_deeply(
        statuses($u),
        { a => 'ready', b => 'init', c => 'init', d => 'init', e => 'failed' },
        'and nothing else is: e failed independently of it'
    );

    my $v = temp_user();
    setup(
        $v, 1,
        a => 'succeeded',
        b => 'succeeded',
        c => 'failed',
        d => 'aborted',
        e => 'succeeded'
    );
    $res = DW::Importer::Control->retry( $v, 1, actor => $actor, items => ['ct_a'] );
    is_deeply(
        statuses($v),
        { a => 'ready', b => 'succeeded', c => 'failed', d => 'init', e => 'succeeded' },
        'a succeeded item can be rerun; items that succeeded are kept'
    );

    # rerunning an item whose own dependency is still failed can't start
    my $w = temp_user();
    setup( $w, 1, a => 'failed', d => 'succeeded' );
    $res = DW::Importer::Control->retry( $w, 1, actor => $actor, items => ['ct_d'] );
    is_deeply( $res->{waiting}, ['ct_d'], 'an item behind a failed dependency waits for it' );
    is( statuses($w)->{d}, 'init', 'as init' );

    my $comm = temp_comm();
    setup( $comm, 1, a => 'succeeded', b => 'failed' );
    DW::Importer::Control->retry( $comm, 1, actor => $actor );
    is( statuses($comm)->{b}, 'ready', 'a community is retried the same way' );
}

# an item the scheduler or a worker moved after retry read it is not clobbered
{
    my $u = temp_user();
    setup( $u, 1, a => 'succeeded', b => 'failed', c => 'aborted' );

    my $read = \&DW::Importer::Control::_statuses;
    no warnings 'redefine';
    local *DW::Importer::Control::_statuses = sub {
        my $status = $read->(@_);
        LJ::get_db_writer()
            ->do( "UPDATE import_items SET status = 'succeeded' WHERE userid = ? AND item = 'ct_b'",
            undef, $u->id );
        return $status;
    };
    my $res = DW::Importer::Control->retry( $u, 1, actor => $actor );

    is( statuses($u)->{b}, 'succeeded', 'an item that changed after it was read is left alone' );
    ok( !( grep { $_ eq 'ct_b' } @{ $res->{reset} } ), 'and not reported as reset' );
}

# cancel aborts an item the scheduler claims between cancel reading it and changing it
{
    my $u = temp_user();
    setup( $u, 1, a => 'succeeded', b => 'ready' );

    my $read = \&DW::Importer::Control::_statuses;
    no warnings 'redefine';
    local *DW::Importer::Control::_statuses = sub {
        my $status = $read->(@_);
        LJ::get_db_writer()
            ->do( "UPDATE import_items SET status = 'queued' WHERE userid = ? AND item = 'ct_b'",
            undef, $u->id );
        return $status;
    };
    my $res = DW::Importer::Control->cancel( $u, 1, actor => $actor );

    is( statuses($u)->{b}, 'aborted', 'an item claimed after cancel read it is still aborted' );
    is_deeply( $res->{aborted}, ['ct_b'], 'and reported' );
}

# retry waits for an import to settle: right after a cancel, a job the scheduler had
# claimed an item for may still be on its way into the queue
{
    my $u = temp_user();
    setup( $u, 1, a => 'failed', b => 'queued' );
    DW::Importer::Control->cancel( $u, 1, actor => $actor );

    is_deeply(
        DW::Importer::Control->retry( $u, 1, actor => $actor ),
        { error => 'settling' },
        'an import that has just changed is not retried'
    );
    is_deeply( statuses($u), { a => 'failed', b => 'aborted' }, 'and not changed' );

    LJ::get_db_writer()
        ->do( 'UPDATE import_items SET last_touch = UNIX_TIMESTAMP() - 120 WHERE userid = ?',
        undef, $u->id );
    is_deeply( DW::Importer::Control->retry( $u, 1, actor => $actor )->{ready},
        ['ct_a'], 'once it has been still for a while it is' );
}

done_testing();
