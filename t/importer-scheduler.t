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
        userid => $u->id,
        log    => sub { push @scheduler_log, sprintf( shift, @_ ) }
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

# two schedulers racing on the same ready item: the other one queues it first, so our
# insert clashes, but the item is live and what waits for it must not be aborted
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio lj_userpics ) );

    {
        no warnings 'redefine';
        local *TheSchwartz::insert = sub {
            LJ::get_db_writer()->do(
                q{UPDATE import_items SET status = 'queued'
                  WHERE userid = ? AND import_data_id = 1 AND item = 'lj_verify'},
                undef, $u->id
            );
            return undef;
        };
        run_for($u);
    }

    is_deeply(
        statuses( $u, 1 ),
        { lj_verify => 'queued', lj_bio => 'init', lj_userpics => 'init' },
        'the item queued by the other scheduler keeps its dependents waiting'
    );
}

done_testing();
