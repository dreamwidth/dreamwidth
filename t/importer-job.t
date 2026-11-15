# t/importer-job.t
#
# Tests the job runner every importer item runs under: how a job's outcome
# becomes an item status, notifications and a TheSchwartz job state. The jobs
# here are trivial test items, not the LiveJournal importer.
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
use Storable qw( thaw );

use DW::Importer::Job;
use DW::Importer::Logger;
use DW::Importer::Outcome;
use DW::Importer::Registry;
use DW::Logic::Importer;

my $reg = 'DW::Importer::Registry';

# the test importer: three items, whose jobs do whatever $Test::Importer::Base::BEHAVE says
{

    package Test::Importer::Base;
    use base 'DW::Importer::Job';

    our ( $BEHAVE, $LOGGER );
    sub max_retries { 3 }
    sub run { my ( $class, $ctx ) = @_; return $BEHAVE->( $class, $ctx ) }

    sub logger_for {
        my ( $class, %args ) = @_;
        return $LOGGER = DW::Importer::Logger->in_memory( job => $args{job} );
    }

    package Test::Importer::First;
    use base 'Test::Importer::Base';

    package Test::Importer::Second;
    use base 'Test::Importer::Base';

    package Test::Importer::Heavy;
    use base 'Test::Importer::Base';
    sub exit_after_job { 1 }
}

my $enabled = 1;
$reg->register_source( name => 'jobtest', kind => 'file', enabled => sub { $enabled } );
$reg->register_item(
    name           => 'jt_first',
    source         => 'jobtest',
    class          => 'Test::Importer::First',
    typeid         => 9401,
    initial_status => 'ready',
    event_noun     => 'first thing has',
);
$reg->register_item(
    name              => 'jt_second',
    source            => 'jobtest',
    class             => 'Test::Importer::Second',
    typeid            => 9402,
    depends_on        => ['jt_first'],
    notify_on_success => 0,
);
$reg->register_item(
    name   => 'jt_heavy',
    source => 'jobtest',
    class  => 'Test::Importer::Heavy',
    typeid => 9403,
);
END { $reg->unregister_source('jobtest') }

# just enough of a TheSchwartz job to see how it ended
{

    package Test::FakeJob;

    sub new {
        my ( $class, %args ) = @_;
        return bless { state => 'untouched', debug => [], %args }, $class;
    }
    sub arg               { $_[0]->{arg} }
    sub failures          { $_[0]->{failures} || 0 }
    sub funcname          { $_[0]->{funcname} }
    sub debug             { push @{ $_[0]->{debug} }, $_[1] }
    sub grabbed_until     { }
    sub save              { }
    sub run_after         { $_[0]->{run_after} = $_[1] }
    sub declined          { $_[0]->{declined} = $_[1] }
    sub completed         { $_[0]->{state} = 'completed' }
    sub failed            { $_[0]->{state} = 'failed'; $_[0]->{message} = $_[1] }
    sub permanent_failure { $_[0]->{state} = 'permanent_failure'; $_[0]->{message} = $_[1] }
}

# an import for $u as the scheduler leaves it: the first item queued
sub setup {
    my ($u) = @_;
    my $dbh = LJ::get_db_writer();
    $dbh->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5, options) '
            . 'VALUES (?, 1, ?, ?, ?, ?)',
        undef,
        $u->id,
        'remote.example',
        'someone',
        'x',
        Storable::nfreeze( { chosen => 'yes' } )
    );
    foreach my $name (qw( jt_first jt_second jt_heavy )) {
        DW::Logic::Importer->set_import_items_for_user(
            $u,
            item => [ $name, $reg->item($name)->{initial_status} ],
            id   => 1
        );
    }
    $dbh->do( "UPDATE import_items SET status = 'queued' WHERE userid = ? AND item = 'jt_first'",
        undef, $u->id );
}

sub run_job {
    my ( $u, $item, $behave, %opts ) = @_;
    $Test::Importer::Base::BEHAVE = $behave;
    my $class = $reg->item($item)->{class};
    my $job   = Test::FakeJob->new(
        arg      => { userid => $u->id, import_data_id => 1 },
        funcname => $class,
        %opts
    );
    $class->work($job);
    return $job;
}

sub status_of {
    my ( $u, $item ) = @_;
    return LJ::get_db_writer()
        ->selectrow_array(
        'SELECT status FROM import_items WHERE userid = ? AND import_data_id = 1 AND item = ?',
        undef, $u->id, $item );
}

# notifications the user has for the import, oldest first
sub events {
    my ($u) = @_;
    my $rows = $u->selectall_arrayref(
        'SELECT status FROM import_status WHERE userid = ? ORDER BY import_status_id',
        undef, $u->id );
    return map { thaw( $_->[0] ) } @$rows;
}

# success: the item succeeds, the user is told once, the job completes, what waited is released
{
    my $u = temp_user();
    setup($u);

    my $seen;
    my $job = run_job( $u, 'jt_first', sub { $seen = $_[1]; return $_[1]->ok } );

    is( status_of( $u, 'jt_first' ),  'succeeded', 'the item succeeded' );
    is( status_of( $u, 'jt_second' ), 'ready',     'what waited for it is ready' );
    is( $job->{state}, 'completed', 'the TheSchwartz job completed' );

    my @events = events($u);
    is( scalar @events,     1,    'the user got one notification' );
    is( $events[0]->{type}, 'ok', 'saying it succeeded' );

    is( $seen->u->id,            $u->id,           'the job was given the target user' );
    is( $seen->data->{hostname}, 'remote.example', 'and the import data' );
    is_deeply( $seen->options, { chosen => 'yes' }, 'with the options the user chose thawed' );
    is( $seen->item->{name}, 'jt_first', 'and the registry entry for its item' );

    like(
        join( '', @{ $job->{debug} } ),
        qr/^\[[\d.]+s [\d.]+s\] Import begun for /,
        'the job log is passed to the job'
    );
}

# an item can be silent on success
{
    my $u = temp_user();
    setup($u);
    my $job = run_job( $u, 'jt_second', sub { $_[1]->ok } );
    is( status_of( $u, 'jt_second' ), 'succeeded', 'a silent item still succeeds' );
    is( scalar( () = events($u) ), 0,           'but the user is not notified' );
    is( $job->{state},             'completed', 'and the job completes' );

    my $loud = temp_user();
    setup($loud);
    run_job( $loud, 'jt_second', sub { $_[1]->ok( show => 1 ) } );
    is( scalar( () = events($loud) ), 1, 'unless the job asks to show it' );
}

# permanent failure: item failed, one notification, job permanently failed, dependents aborted
{
    my $u = temp_user();
    setup($u);

    my $job = run_job( $u, 'jt_first', sub { $_[1]->fail( 'It broke: %s, 100%% sure', 'badly' ) } );
    is( status_of( $u, 'jt_first' ),  'failed',  'the item failed' );
    is( status_of( $u, 'jt_second' ), 'aborted', 'what waited for it was aborted' );
    is( status_of( $u, 'jt_heavy' ),  'init',    'unrelated items are untouched' );
    is( $job->{state},   'permanent_failure',          'the job failed for good' );
    is( $job->{message}, 'It broke: badly, 100% sure', 'with the message' );

    my @events = events($u);
    is( scalar @events,     1,                            'one notification' );
    is( $events[0]->{type}, 'fail',                       'that it failed' );
    is( $events[0]->{msg},  'It broke: badly, 100% sure', 'with the message' );
}

# a remote's error text is kept exactly, even with printf directives in it
{
    my $u = temp_user();
    setup($u);
    my $text = 'Remote said 50% of %s failed';
    my $job  = run_job( $u, 'jt_first', sub { $_[1]->fail($text) } );
    is( $job->{message}, $text, 'message with directives and no arguments is not formatted' );
}

# temporary failure: the item stays in the queue to be retried, with a notification
{
    my $u = temp_user();
    setup($u);

    my $job = run_job( $u, 'jt_first', sub { $_[1]->temp_fail('Try later') }, failures => 1 );
    is( status_of( $u, 'jt_first' ),  'queued', 'the item is still queued' );
    is( status_of( $u, 'jt_second' ), 'init',   'and nothing waiting for it moves' );
    is( $job->{state},   'failed',    'the TheSchwartz job is failed, so it will be retried' );
    is( $job->{message}, 'Try later', 'with the message' );

    my @events = events($u);
    is( scalar @events,         1,           'one notification' );
    is( $events[0]->{type},     'temp_fail', 'that it will be retried' );
    is( $events[0]->{failures}, 1,           'saying how many times it has failed' );
    is( $events[0]->{retries},  3,           'and how many retries there are' );
}

# the last retry gives up for good
{
    my $u = temp_user();
    setup($u);

    my $job = run_job( $u, 'jt_first', sub { $_[1]->temp_fail('Still broken') }, failures => 2 );
    is( status_of( $u, 'jt_first' ),  'failed',  'after max_retries failures the item fails' );
    is( status_of( $u, 'jt_second' ), 'aborted', 'and what waited for it is aborted' );
    is( $job->{state}, 'permanent_failure', 'the TheSchwartz job is failed permanently' );

    my @events = events($u);
    is( scalar @events,     1,      'one notification' );
    is( $events[0]->{type}, 'fail', 'which says it will not be retried' );
}

# anything a job dies with is a temporary failure; an outcome it dies with is honoured
{
    my $u = temp_user();
    setup($u);
    my $job = run_job( $u, 'jt_first', sub { die "kaboom\nsecond line\n" } );
    is( $job->{state}, 'failed', 'an exception is a temporary failure' );
    is( $job->{message}, 'Failure running job: kaboom second line ', 'with the text on one line' );
    is( status_of( $u, 'jt_first' ), 'queued', 'and the item stays queued' );

    my $v = temp_user();
    setup($v);
    $job = run_job( $v, 'jt_first', sub { die DW::Importer::Outcome->fail('from deep inside') } );
    is( $job->{state},   'permanent_failure', 'a failure outcome can be raised from anywhere' );
    is( $job->{message}, 'from deep inside',  'with its message' );
    is( status_of( $v, 'jt_first' ), 'failed', 'and the item fails' );
}

# a community's import notifies every maintainer
{
    my $comm        = temp_comm();
    my @maintainers = ( temp_user(), temp_user() );
    LJ::set_rel( $comm->id, $_->id, 'A' ) foreach @maintainers;
    setup($comm);

    run_job( $comm, 'jt_first', sub { $_[1]->ok } );
    is( scalar( () = events($_) ), 1, 'each maintainer is notified: ' . $_->user )
        foreach @maintainers;
    is( scalar( () = events($comm) ), 0, 'the community itself is not' );

    my $comm2 = temp_comm();
    LJ::set_rel( $comm2->id, $_->id, 'A' ) foreach @maintainers;
    setup($comm2);
    run_job( $comm2, 'jt_first', sub { $_[1]->fail('nope') } );
    is( scalar( () = events($_) ), 2, 'and told about failures too: ' . $_->user )
        foreach @maintainers;
}

# a source that is switched off declines the job without touching the item
{
    my $u = temp_user();
    setup($u);

    $enabled = 0;
    my $ran = 0;
    my $job = run_job( $u, 'jt_first', sub { $ran++; $_[1]->ok } );
    $enabled = 1;

    ok( !$ran,                      'a disabled source does not run' );
    ok( $job->{declined},           'the job is declined' );
    ok( $job->{run_after} > time(), 'to run again later' );
    is( status_of( $u, 'jt_first' ), 'queued', 'the item is untouched' );
    is( scalar( () = events($u) ), 0, 'and the user is not notified' );
}

# nothing carries over from one job to the next
{
    my @cache_at_start;
    my $behave = sub {
        my ( $class, $ctx ) = @_;
        push @cache_at_start, scalar keys %{ $ctx->cache };
        $ctx->cache->{remembered} = 1;
        return $ctx->ok;
    };
    foreach ( 1 .. 2 ) {
        my $u = temp_user();
        setup($u);
        run_job( $u, 'jt_first', $behave );
    }
    is_deeply( \@cache_at_start, [ 0, 0 ], 'each job starts with an empty cache' );
}

# jobs that leak memory ask for the process to exit, without exiting
{
    DW::Importer::Job->reset_exit_request;
    my $u = temp_user();
    setup($u);

    run_job( $u, 'jt_first', sub { $_[1]->ok } );
    ok( !DW::Importer::Job->exit_requested, 'an ordinary job leaves the process alone' );

    run_job( $u, 'jt_heavy', sub { $_[1]->ok } );
    ok( DW::Importer::Job->exit_requested, 'a heavy job asks for the process to exit afterwards' );
    DW::Importer::Job->reset_exit_request;
}

# a job's own log is kept by the logger it was given
{
    my $u = temp_user();
    setup($u);
    run_job( $u, 'jt_first', sub { $_[1]->log( 'found %d things', 3 ); $_[1]->ok } );
    ok( ( grep { $_ eq 'found 3 things' } $Test::Importer::Base::LOGGER->messages ),
        'ctx->log writes to the logger' );
}

done_testing();
