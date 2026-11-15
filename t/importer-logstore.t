# t/importer-logstore.t
#
# Tests that import job logs are kept in blob storage with an index row: they come
# back whole and in order across chunks, an expired chunk is reported rather than
# fatal, and a broken store never makes logging (or so the import) fail.
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

use Encode;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );

use DW::BlobStore;
use DW::Importer::LogStore;
use DW::Importer::Logger;

my $u = temp_user();

{

    package Test::Job;
    sub new { bless { lines => [] }, shift }
    sub debug { push @{ $_[0]->{lines} }, $_[1] }
}

my $import = 0;

# a logger for a fresh import, and the number of it
sub logger {
    my %opts = @_;
    $import++;
    return (
        DW::Importer::Logger->for_job(
            job            => $opts{job},
            userid         => $u->id,
            import_data_id => $import,
            item           => $opts{item} || 'lj_entries'
        ),
        $import
    );
}

# the text of an import's one log, and how many chunks could not be retrieved
sub stored {
    my ($impid) = @_;
    my $logs = DW::Importer::LogStore->logs_for( $u->id, $impid );
    is( scalar @$logs, 1, "import $impid has one log" );
    my ( $text, $missing ) = DW::Importer::LogStore->content( $logs->[0] );
    return ( $text, $missing, $logs->[0] );
}

sub body {
    return join '', map { $_ =~ s/^\[[^\]]*\] //r } split /^/, $_[0];
}

# lines come back whole and in order across chunks
{
    local $DW::Importer::Logger::FLUSH_BYTES = 200;
    my $job = Test::Job->new;
    my ( $logger, $impid ) = logger( job => $job );
    ok( defined $logger->logid, 'the log was started' );

    $logger->log( 'line %d', $_ ) foreach 1 .. 60;
    $logger->log("a wide character: \x{2603} and e-acute \x{e9}");
    $logger->close;

    my ( $text, $missing, $row ) = stored($impid);
    is( $missing,       0,              'nothing is missing' );
    is( $row->{logid},  $logger->logid, 'the index row is the logger\'s log' );
    is( $row->{item},   'lj_entries',   'it records the item' );
    is( $row->{userid}, $u->id,         'and whose it is' );
    is( $row->{pid},    $$,             'and the process that wrote it' );
    ok( $row->{chunks} > 3, 'which took several chunks' );
    is( $row->{bytes}, length( Encode::encode( 'UTF-8', $text ) ), 'with the bytes recorded' );

    my @lines = split /^/, body($text);
    like( $lines[0], qr/^Log started at /, 'the first line says when it started' );
    is_deeply(
        [ @lines[ 1 .. 60 ] ],
        [ map { "line $_\n" } 1 .. 60 ],
        'the lines are all there, in order'
    );
    is( $lines[61], "a wide character: \x{2603} and e-acute \x{e9}\n", 'wide characters survive' );
    is( scalar @lines, 62, 'and nothing else' );

    is( scalar @{ $job->{lines} }, 61, 'every line still went to the job\'s debug output' );

    is_deeply( DW::Importer::LogStore->log( $row->{logid} ), $row, 'the log can be fetched by id' );
    is( DW::Importer::LogStore->log(0), undef, 'a log that does not exist is undef' );
}

# logs of an import are its own, oldest first
{
    my ( $one, $impid ) = logger( item => 'lj_comments' );
    $one->log('first');
    $one->close;
    my $two = DW::Importer::Logger->for_job(
        userid         => $u->id,
        import_data_id => $impid,
        item           => 'lj_tags'
    );
    $two->log('second');
    $two->close;

    my $logs = DW::Importer::LogStore->logs_for( $u->id, $impid );
    is_deeply(
        [ map { $_->{item} } @$logs ],
        [ 'lj_comments', 'lj_tags' ],
        'an import\'s logs come back oldest first'
    );
    is_deeply( DW::Importer::LogStore->logs_for( $u->id, $impid + 1000 ),
        [], 'and another import has none of them' );
}

# the time since the last write is checked on each line
{
    local $DW::Importer::Logger::FLUSH_BYTES = 1_000_000;
    my ( $logger, $impid ) = logger();
    $logger->log('early');
    is( DW::Importer::LogStore->logs_for( $u->id, $impid )->[0]->{chunks},
        0, 'a few lines wait in the buffer' );

    $logger->{last_flush} -= $DW::Importer::Logger::FLUSH_SECONDS + 1;
    $logger->log('late');
    is( DW::Importer::LogStore->logs_for( $u->id, $impid )->[0]->{chunks},
        1, 'but are written once enough time has passed' );
    $logger->close;
    my ($text) = stored($impid);
    like( body($text), qr/\nearly\nlate\n\z/, 'with both lines' );
}

# a logger that is dropped without closing still writes what it has
{
    my ( $logger, $impid ) = logger();
    $logger->log('left behind');
    undef $logger;
    my ($text) = stored($impid);
    like( $text, qr/left behind\n/, 'a logger that goes out of scope writes its buffer' );
}

# an expired chunk is reported, not fatal
{
    local $DW::Importer::Logger::FLUSH_BYTES = 100;
    my ( $logger, $impid ) = logger();
    $logger->log( 'line %02d of the log', $_ ) foreach 1 .. 30;
    $logger->close;

    my ( $whole, undef, $row ) = stored($impid);
    my $key = join '/', $u->id, $impid, $row->{logid}, 1;
    ok( DW::BlobStore->delete( importlogs => $key ), 'a chunk expires' );

    my ( $text, $missing ) = DW::Importer::LogStore->content($row);
    is( $missing, 1, 'it is counted as missing' );
    ok( length $text && length $text < length $whole, 'and the rest of the log is still returned' );
    like( $text, qr/line 30 of the log/, 'including the end' );
}

# a broken store never makes logging fail, and what it missed is written once it recovers
{
    local $DW::Importer::Logger::FLUSH_BYTES = 100;
    my ( $logger, $impid ) = logger();
    $logger->log('before the outage');

    {
        no warnings 'redefine';
        local *DW::BlobStore::store = sub { return 0 };
        ok( eval { $logger->log( 'during the outage %d', $_ ) foreach 1 .. 20; 1 },
            'logging while the store refuses chunks does not die' )
            or diag($@);
    }
    {
        no warnings 'redefine';
        local *DW::BlobStore::store = sub { die "the store blew up\n" };
        ok( eval { $logger->log( 'still down %d', $_ ) foreach 1 .. 5; 1 },
            'nor does a store that throws' )
            or diag($@);
    }
    my $row = DW::Importer::LogStore->logs_for( $u->id, $impid )->[0];
    is( $row->{chunks}, 0, 'nothing was recorded for what could not be stored' );

    $logger->{last_flush} -= $DW::Importer::Logger::FLUSH_SECONDS + 1;
    $logger->log('after the outage');
    $logger->close;

    my ($text) = stored($impid);
    my $log = body($text);
    like(
        $log,
qr/before the outage\n.*during the outage 1\n.*during the outage 20\n.*still down 5\n.*after the outage\n/s,
        'the lines from the outage are written in order once it is over'
    );
}

# an outage that outlasts the buffer drops the oldest lines, with a marker, instead of
# growing without bound
{
    local $DW::Importer::Logger::FLUSH_BYTES = 100;
    local $DW::Importer::Logger::MAX_BUFFER  = 500;
    my ( $logger, $impid ) = logger();

    {
        no warnings 'redefine';
        local *DW::BlobStore::store = sub { return 0 };
        $logger->log( 'outage line %03d', $_ ) foreach 1 .. 100;
    }
    ok( length $logger->{buffer} <= 500, 'the buffer stays under its cap' );

    $logger->log('recovered');
    $logger->close;

    my ($text) = stored($impid);
    like( $text, qr/\[\d+ earlier lines were dropped/, 'a marker says lines were dropped' );
    like( $text, qr/outage line 100\n.*recovered\n/s,  'the newest lines were kept' );
    unlike( $text, qr/outage line 001\n/, 'and the oldest were not' );
}

# a log that could not be started is started when the store comes back
{
    my $logger;
    my $impid;
    {
        no warnings 'redefine';
        local *DW::Importer::LogStore::start = sub { return undef };
        ( $logger, $impid ) = logger();
        ok( !defined $logger->logid, 'a log that could not be started has no id' );
        ok( eval { $logger->log('written blind'); 1 }, 'but logging does not die' );
    }

    $logger->log('now it can');
    $logger->close;
    ok( defined $logger->logid, 'the log was started later' );
    my ($text) = stored($impid);
    like( $text, qr/Log started.*written blind\n.*now it can\n/s,
        'and has what was logged before' );
}

done_testing();
