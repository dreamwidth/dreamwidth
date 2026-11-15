# t/importer-queue.t
#
# Tests how the importer decides that an item has no TheSchwartz job. "No job" has
# to mean every queue database was read, because a running job that is in one that
# could not be would be mistaken for a lost one and its item run twice.
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
use DBI;
use LJ::Test qw( temp_user );
use TheSchwartz;
use TheSchwartz::Job;

use DW::Importer::Queue;
use DW::Importer::Registry;
use DW::Importer::Scheduler;
use DW::Logic::Importer;

my $reg   = 'DW::Importer::Registry';
my $class = $reg->item('lj_entries')->{class};

# a queue database of its own, made the way the fake queue is
sub make_queue_db {
    my ($name) = @_;
    my $file = "$LJ::HOME/t-queue-$name-$$.sqlite";
    unlink $file;

    my $dbh =
        DBI->connect( "dbi:SQLite:dbname=$file", '', '', { RaiseError => 1, PrintError => 0 } );
    open my $fh, '<', "$LJ::HOME/t/data/schema-sqlite.sql" or die $!;
    my $sql = do { local $/; <$fh> };
    $dbh->do($_) foreach grep { /\S/ } split /;\s*/, $sql;
    $dbh->disconnect;
    return $file;
}

my @files;
END { unlink @files }

sub queue {
    my (@dsns) = @_;
    return TheSchwartz->new( databases => [ map { { dsn => $_, user => '', pass => '' } } @dsns ] );
}

sub add_job {
    my ( $client, $u, $impid ) = @_;
    my $job = TheSchwartz::Job->new(
        funcname => $class,
        uniqkey  => 'lj_entries-' . $u->id,
        arg      => { userid => $u->id, import_data_id => $impid },
    );
    $client->insert($job) or die 'could not add the job';
}

sub in_queue {
    my ( $client, $code ) = @_;
    no warnings 'redefine';
    local *LJ::theschwartz = sub { return $client };
    return $code->();
}

my $good1 = make_queue_db('one');
my $good2 = make_queue_db('two');
push @files, $good1, $good2;
my @dsn  = map { "dbi:SQLite:dbname=$_" } $good1, $good2;
my $down = 'dbi:SQLite:dbname=/nonexistent-directory/queue.sqlite';

# a row that has been queued long enough to be looked at
sub stale_row {
    my ($u) = @_;
    DW::Logic::Importer->set_import_items_for_user( $u, item => [ 'lj_entries', 'init' ], id => 1 );
    LJ::get_db_writer()->do(
        q{UPDATE import_items SET status = 'queued', last_touch = UNIX_TIMESTAMP() - 7200
          WHERE userid = ? AND import_data_id = 1 AND item = 'lj_entries'},
        undef, $u->id
    );
}

sub status_of {
    my ($u) = @_;
    return LJ::get_db_writer()->selectrow_array(
q{SELECT status FROM import_items WHERE userid = ? AND import_data_id = 1 AND item = 'lj_entries'},
        undef, $u->id
    );
}

sub recover {
    my ($u) = @_;
    return DW::Importer::Scheduler->recover_stale_claims(
        dbh    => LJ::get_db_writer(),
        userid => $u->id
    );
}

# every database read, and no job: there is none, and the lost item is made ready again
{
    my $u      = temp_user();
    my $client = queue(@dsn);
    stale_row($u);

    is(
        in_queue(
            $client, sub { DW::Importer::Queue->job_count( $u, 'lj_entries', import_data_id => 1 ) }
        ),
        0,
        'with every database read and no job, the count is 0'
    );
    is( in_queue( $client, sub { recover($u) } ), 1, 'so the stale item is recovered' );
    is( status_of($u), 'ready', 'and is ready again' );
}

# a job in any database is found
{
    my $u      = temp_user();
    my $client = queue(@dsn);
    add_job( queue( $dsn[1] ), $u, 1 );
    is(
        in_queue(
            $client, sub { DW::Importer::Queue->job_count( $u, 'lj_entries', import_data_id => 1 ) }
        ),
        1,
        'a job in the second database is found'
    );
    is(
        in_queue(
            $client, sub { DW::Importer::Queue->job_count( $u, 'lj_entries', import_data_id => 2 ) }
        ),
        0,
        'but not as the job of another import'
    );
}

# one database that cannot be connected to: a missing job is not known to be missing
{
    my $u      = temp_user();
    my $client = queue( $dsn[0], $down );
    stale_row($u);

    is(
        in_queue(
            $client, sub { DW::Importer::Queue->job_count( $u, 'lj_entries', import_data_id => 1 ) }
        ),
        undef,
        'with one database unreachable, no job found is unknown'
    );
    is( in_queue( $client, sub { recover($u) } ), 0, 'so nothing is recovered' );
    is( status_of($u), 'queued', 'and the item stays queued' );

    add_job( queue( $dsn[0] ), $u, 1 );
    is(
        in_queue(
            $client, sub { DW::Importer::Queue->job_count( $u, 'lj_entries', import_data_id => 1 ) }
        ),
        1,
        'a job that was seen is still a job while another database is down'
    );
}

# a query that fails is not an empty answer
{
    my $u = temp_user();

    # a database with no tables: connecting works, reading does not
    my $empty = "$LJ::HOME/t-queue-empty-$$.sqlite";
    push @files, $empty;
    unlink $empty;
    DBI->connect( "dbi:SQLite:dbname=$empty", '', '', { RaiseError => 1 } )->disconnect;

    my $client = queue( $dsn[0], "dbi:SQLite:dbname=$empty" );
    stale_row($u);
    is(
        in_queue(
            $client, sub { DW::Importer::Queue->job_count( $u, 'lj_entries', import_data_id => 1 ) }
        ),
        undef,
        'when the funcmap can not be read the answer is unknown'
    );
    is( in_queue( $client, sub { recover($u) } ), 0, 'and nothing is recovered' );
    is( status_of($u), 'queued', 'the item stays queued' );

    # funcmap fine, job table gone
    my $nojob = make_queue_db('nojob');
    push @files, $nojob;
    my $h = DBI->connect( "dbi:SQLite:dbname=$nojob", '', '', { RaiseError => 1 } );
    $h->do( 'INSERT INTO funcmap (funcname) VALUES (?)', undef, $class );
    $h->do('DROP TABLE job');
    $h->disconnect;
    my $u2 = temp_user();
    stale_row($u2);
    $client = queue( $dsn[0], "dbi:SQLite:dbname=$nojob" );
    is(
        in_queue(
            $client,
            sub { DW::Importer::Queue->job_count( $u2, 'lj_entries', import_data_id => 1 ) }
        ),
        undef,
        'when the job query fails the answer is unknown'
    );
    is( in_queue( $client, sub { recover($u2) } ), 0, 'and nothing is recovered' );
}

# no queue at all is unknown too
{
    my $u = temp_user();
    is( in_queue( undef, sub { DW::Importer::Queue->job_count( $u, 'lj_entries' ) } ),
        undef, 'no queue client: unknown' );
}

done_testing();
