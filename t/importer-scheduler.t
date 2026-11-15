# t/importer-scheduler.t
#
# Tests the import scheduler: ready items become TheSchwartz jobs for the
# registered worker classes, stale imports are dropped, and a job that cannot
# be queued aborts the items waiting for it.
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
use LJ::Test qw( temp_user );
use TheSchwartz::Job;

use DW::Importer::Items;
use DW::Importer::Registry;
use DW::Importer::Scheduler;
use DW::Logic::Importer;

my $reg = 'DW::Importer::Registry';

sub start_import {
    my ( $u, $impid, @items ) = @_;
    foreach my $name (@items) {
        my $err = DW::Logic::Importer->set_import_items_for_user(
            $u,
            item => [ $name, $reg->item($name)->{initial_status} ],
            id   => $impid
        );
        die $err if $err;
    }
}

sub statuses {
    my ( $u, $impid ) = @_;
    my $rows =
        LJ::get_db_writer()
        ->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $impid );
    return { map { $_->[0] => $_->[1] } @$rows };
}

# every job in the fake queue, as "funcname uniqkey import_data_id"
sub queued {
    my ($u) = @_;
    my @jobs = LJ::theschwartz()
        ->list_jobs( { funcname => [ $reg->classes ], run_after => time() + 100 } );
    return sort map { join ' ', $_->funcname, $_->uniqkey, $_->arg->{import_data_id} }
        grep { $_->arg->{userid} == $u->id } @jobs;
}

my @scheduler_log;

sub run_for {
    my ($u) = @_;
    @scheduler_log = ();
    DW::Importer::Scheduler->run_once(
        userid           => $u->id,
        recover_interval => 0,
        log              => sub { push @scheduler_log, sprintf( shift, @_ ) }
    );
}

# ready items are queued under their registered worker class, and nothing else is
{
    my $u = temp_user();
    start_import( $u, 1, map { $_->{name} } $reg->items('livejournal') );

    run_for($u);

    my $verify = $reg->item('lj_verify')->{class};
    is_deeply(
        [ queued($u) ],
        [ "$verify lj_verify-" . $u->id . " 1" ],
        'verify is queued, with a uniqkey per item and user'
    );
    is( statuses( $u, 1 )->{lj_verify}, 'queued', 'and marked queued' );
    is( statuses( $u, 1 )->{lj_bio},    'init',   'items still waiting are left alone' );
    is( $u->prop('import_job'), 1, 'the user is pointed at the import being run' );

    # the worker finishing readies the next group, which the next pass picks up
    DW::Importer::Items->advance( $u, 1, 'lj_verify', 'success' );
    LJ::get_db_writer()
        ->do(
        "UPDATE import_items SET status = 'succeeded' WHERE userid = ? AND item = 'lj_verify'",
        undef, $u->id );

    run_for($u);
    my @expected = sort map { $reg->item($_)->{class} . " $_-" . $u->id . " 1" }
        qw( lj_verify lj_bio lj_userpics lj_friendgroups lj_tags );
    is_deeply( [ queued($u) ],
        \@expected, 'all four items verify made ready are queued by one pass' );
    is( statuses( $u, 1 )->{$_}, 'queued', "$_ is queued" )
        foreach qw( lj_bio lj_userpics lj_friendgroups lj_tags );
    is( statuses( $u, 1 )->{lj_entries}, 'init', 'entries still wait for friend groups' );
}

# nothing to do is not an error
{
    my $u = temp_user();
    run_for($u);
    is_deeply( \@scheduler_log, ['nothing to do'], 'a user with nothing ready is skipped' );
}

# when a newer import exists, the older one's ready items are dropped rather than run
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    start_import( $u, 2, qw( lj_bio ) );             # import 2 has nothing ready

    run_for($u);
    is( statuses( $u, 1 )->{lj_verify}, 'aborted', 'the older import is aborted' );
    is_deeply( [ queued($u) ], [], 'and nothing was queued for it' );
}

# if an earlier job for the same item is still in the queue, this one is aborted, and so is
# anything that was waiting for it
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio lj_userpics ) );

    # something already queued for lj_verify of this user
    my $job = TheSchwartz::Job->new(
        funcname => $reg->item('lj_verify')->{class},
        uniqkey  => 'lj_verify-' . $u->id,
        arg      => { userid => $u->id, import_data_id => 0 },
    );
    LJ::theschwartz()->insert($job) or die 'could not seed the queue';

    run_for($u);
    like( join( "\n", @scheduler_log ), qr/already have lj_verify queued/, 'the clash is logged' );
    is_deeply(
        statuses( $u, 1 ),
        { lj_verify => 'aborted', lj_bio => 'aborted', lj_userpics => 'aborted' },
        'the item and what waited for it are aborted'
    );
}

# run the scheduler for $u, calling the 'before' and 'after' subs around its first job
# insert, to interleave other work with it
sub run_with_insert_hook {
    my ( $u, %hooks ) = @_;
    my $orig = \&TheSchwartz::insert;
    my $in_hook;
    no warnings 'redefine';
    local *TheSchwartz::insert = sub {
        return $orig->(@_) if $in_hook;
        $in_hook = 1;
        $hooks{before}->() if $hooks{before};
        my $rv = $orig->(@_);
        $hooks{after}->() if $hooks{after};
        return $rv;
    };
    run_for($u);
}

# a second scheduler running just after the first inserted the job must leave the item
# alone: it is already claimed, so nothing is aborted and only one job exists
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio lj_userpics ) );

    run_with_insert_hook( $u, after => sub { run_for($u) } );

    is_deeply(
        statuses( $u, 1 ),
        { lj_verify => 'queued', lj_bio => 'init', lj_userpics => 'init' },
        'the claimed item keeps its dependents waiting'
    );
    is( scalar( grep { /^\S+ lj_verify-/ } queued($u) ), 1, 'and only one job was queued' );
}

# a job that runs and finishes as soon as it is inserted keeps its result
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );

    run_with_insert_hook(
        $u,
        after => sub {
            LJ::get_db_writer()->do(
                q{UPDATE import_items SET status = 'succeeded'
                  WHERE userid = ? AND import_data_id = 1 AND item = 'lj_verify'},
                undef, $u->id
            );
        }
    );

    is( statuses( $u, 1 )->{lj_verify}, 'succeeded', 'the finished status is not overwritten' );
}

# a job insert that throws is handled like one that clashes: the claimed row must not be left
# queued with no job, since nothing would ever pick it up
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio lj_userpics ) );

    {
        no warnings 'redefine';
        local *TheSchwartz::insert = sub { die "database went away\n" };
        run_for($u);
    }

    like(
        join( "\n", @scheduler_log ),
        qr/inserting the job for lj_verify failed: database went away/,
        'the error is logged'
    );
    is_deeply(
        statuses( $u, 1 ),
        { lj_verify => 'aborted', lj_bio => 'aborted', lj_userpics => 'aborted' },
        'the row and what waited for it are aborted'
    );
}

# an item queued long ago with no job (the scheduler died after claiming it) is made ready
# again and scheduled; one that is fresh, or still has its job, is not touched
sub set_queued {
    my ( $u, $item, $age ) = @_;
    LJ::get_db_writer()->do(
        q{UPDATE import_items SET status = 'queued', last_touch = UNIX_TIMESTAMP() - ?
          WHERE userid = ? AND import_data_id = 1 AND item = ?},
        undef, $age, $u->id, $item
    );
}

sub touched {
    my ( $u, $item ) = @_;
    return LJ::get_db_writer()->selectrow_array(
        'SELECT last_touch FROM import_items WHERE userid = ? AND import_data_id = 1 AND item = ?',
        undef, $u->id, $item
    );
}

{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    set_queued( $u, 'lj_verify', 7200 );

    run_for($u);
    like(
        join( "\n", @scheduler_log ),
        qr/1:lj_verify of user @{[ $u->id ]} was queued with no job/,
        'the recovery is logged'
    );
    is( statuses( $u, 1 )->{lj_verify}, 'queued', 'the stale item is queued again' );
    is_deeply(
        [ queued($u) ],
        [ $reg->item('lj_verify')->{class} . ' lj_verify-' . $u->id . ' 1' ],
        'and now has a job'
    );
    ok( touched( $u, 'lj_verify' ) > time() - 100, 'with a fresh claim time' );
}

{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    set_queued( $u, 'lj_verify', 7200 );
    my $before = touched( $u, 'lj_verify' );

    LJ::theschwartz()->insert(
        TheSchwartz::Job->new(
            funcname => $reg->item('lj_verify')->{class},
            uniqkey  => 'lj_verify-' . $u->id,
            arg      => { userid => $u->id, import_data_id => 1 },
        )
    ) or die 'could not seed the queue';

    run_for($u);
    is( statuses( $u, 1 )->{lj_verify}, 'queued', 'a stale item whose job exists stays queued' );
    is( touched( $u, 'lj_verify' ), $before, 'and is not touched' );
    is( scalar( () = queued($u) ), 1, 'no second job was added' );
}

{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    set_queued( $u, 'lj_verify', 60 );

    run_for($u);
    is( statuses( $u, 1 )->{lj_verify},
        'queued', 'a recently queued item with no job is left alone' );
    is_deeply( [ queued($u) ], [], 'and nothing is scheduled for it' );
    is_deeply( \@scheduler_log, ['nothing to do'], 'as there is nothing to do' );
}

# if the queue can't be read, "no job found" means nothing and nothing is changed
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    set_queued( $u, 'lj_verify', 7200 );

    {
        no warnings 'redefine';
        local *LJ::theschwartz = sub { return undef };
        run_for($u);
    }
    is( statuses( $u, 1 )->{lj_verify}, 'queued', 'an unreadable queue does not reset anything' );
    is( touched( $u, 'lj_verify' ) < time() - 7000, 1, 'and does not touch the row' );
}

# the age after which a claim is stale can be configured
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    set_queued( $u, 'lj_verify', 300 );

    local $LJ::IMPORTER_STALE_CLAIM_SECONDS = 120;
    run_for($u);
    is_deeply(
        [ queued($u) ],
        [ $reg->item('lj_verify')->{class} . ' lj_verify-' . $u->id . ' 1' ],
        'a claim older than the configured age is recovered'
    );
}

done_testing();
