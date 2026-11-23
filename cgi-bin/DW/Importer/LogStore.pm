#!/usr/bin/perl
#
# DW::Importer::LogStore
#
# Where the logs of import jobs are kept, so they can be read from any host.
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

package DW::Importer::LogStore;

=head1 NAME

DW::Importer::LogStore - Import job logs in blob storage, indexed in the database

=head1 SYNOPSIS

    my $logid = DW::Importer::LogStore->start( $userid, $import_data_id, 'lj_entries' );
    DW::Importer::LogStore->append_chunk( $logid, $userid, $import_data_id, \$text );

    foreach my $log ( @{ DW::Importer::LogStore->logs_for( $userid, $import_data_id ) } ) {
        my ( $text, $missing ) = DW::Importer::LogStore->content($log);
    }

=head1 DESCRIPTION

A job's log is one row in C<import_logs> (which job, when, how big, which host and process
wrote it) and a run of chunks in L<DW::BlobStore>, namespace C<importlogs>, keys
C<E<lt>useridE<gt>/E<lt>import_data_idE<gt>/E<lt>logidE<gt>/E<lt>nE<gt>> with C<n> counting
from 0. The row's C<chunks> is only raised once a chunk is stored, so a chunk number below it
that cannot be retrieved has expired, not never existed.

Nothing here deletes anything. Production should expire the blobs with S3 lifecycle rules of
about 30 days on the C<E<lt>prefixE<gt>/importlogs/> and C<E<lt>prefixE<gt>/importcache/>
(the comment export cache, see L<DW::Importer::Source::LiveJournal::Transport>) key
prefixes: L<DW::BlobStore::S3> lays keys out as C<E<lt>prefixE<gt>/E<lt>namespaceE<gt>/E<lt>hashE<gt>>,
so a prefix rule covers a namespace. The index rows are tiny and stay; a log whose chunks have
expired reads back with those chunks counted as missing.

Writing is best effort: C<start> and C<append_chunk> warn and report failure rather than die,
because a log must never fail the import it describes.

=cut

use strict;
use warnings;

use Log::Log4perl;
use Sys::Hostname qw( hostname );

use DW::BlobStore;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $NAMESPACE = 'importlogs';
my @COLUMNS   = qw( logid userid import_data_id item started updated chunks bytes host pid );

sub _chunk_key {
    my ( $userid, $import_data_id, $logid, $n ) = @_;
    return "$userid/$import_data_id/$logid/$n";
}

=head2 C<< DW::Importer::LogStore->start( $userid, $import_data_id, $item ) >>

Starts a log for a job of the import, recording this host and process. Returns its id, or
undef (after warning) if the row could not be made.

=cut

sub start {
    my ( $class, $userid, $import_data_id, $item ) = @_;

    my $dbh = LJ::get_db_writer();
    unless ($dbh) {
        $log->warn('Could not start an import log: no database handle.');
        return undef;
    }

    my $now = time();
    $dbh->do(
        q{INSERT INTO import_logs
            (userid, import_data_id, item, started, updated, chunks, bytes, host, pid)
          VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)},
        undef, $userid, $import_data_id, $item, $now, $now, hostname(), $$
    );
    if ( $dbh->err ) {
        $log->warn( 'Could not start an import log: ' . $dbh->errstr );
        return undef;
    }

    return $dbh->{mysql_insertid} + 0;
}

=head2 C<< DW::Importer::LogStore->append_chunk( $logid, $userid, $import_data_id, \$text ) >>

Stores C<$text> as the log's next chunk, then records it in the row. Returns true if it was
stored; otherwise warns and returns false, and the log is as it was (storing the same text
again is safe).

C<$text> should be UTF-8 bytes, as L<DW::Importer::Logger> buffers it; a string of
characters is encoded to UTF-8 first. C<content> returns the bytes as they were stored.

=cut

sub append_chunk {
    my ( $class, $logid, $userid, $import_data_id, $textref ) = @_;
    return 0 unless defined $$textref && length $$textref;

    my $dbh = LJ::get_db_writer();
    unless ($dbh) {
        $log->warn("Could not append to import log $logid: no database handle.");
        return 0;
    }

    my ($n) =
        $dbh->selectrow_array( 'SELECT chunks FROM import_logs WHERE logid = ?', undef, $logid );
    unless ( defined $n ) {
        $log->warn( "Could not find import log $logid to append to"
                . ( $dbh->err ? ': ' . $dbh->errstr : '.' ) );
        return 0;
    }

    my $bytes = $$textref;
    utf8::encode($bytes) if utf8::is_utf8($bytes);
    my $key    = _chunk_key( $userid, $import_data_id, $logid, $n );
    my $stored = eval { DW::BlobStore->store( $NAMESPACE => $key, \$bytes ) };
    unless ($stored) {
        $log->warn( "Could not store chunk $n of import log $logid" . ( $@ ? ": $@" : '.' ) );
        return 0;
    }

    # only now does the chunk count, so a reader never meets a chunk the store never had
    $dbh->do(
        q{UPDATE import_logs SET chunks = chunks + 1, bytes = bytes + ?, updated = ?
          WHERE logid = ?},
        undef, length($bytes), time(), $logid
    );
    if ( $dbh->err ) {
        $log->warn(
            "Stored chunk $n of import log $logid but could not record it: " . $dbh->errstr );
        return 0;
    }

    return 1;
}

=head2 C<< DW::Importer::LogStore->logs_for( $userid, $import_data_id ) >>

The logs of one import, oldest first, each a hashref of C<logid>, C<userid>,
C<import_data_id>, C<item>, C<started>, C<updated>, C<chunks>, C<bytes>, C<host> and C<pid>.

=cut

sub logs_for {
    my ( $class, $userid, $import_data_id ) = @_;

    my $dbr = LJ::get_db_reader() or return [];
    return $dbr->selectall_arrayref(
              'SELECT '
            . join( ', ', @COLUMNS )
            . ' FROM import_logs
         WHERE userid = ? AND import_data_id = ? ORDER BY started, logid',
        { Slice => {} }, $userid, $import_data_id
    ) || [];
}

=head2 C<< DW::Importer::LogStore->log( $logid ) >>

The hashref (as C<logs_for> returns) for one log, or undef if there isn't one.

=cut

sub log {
    my ( $class, $logid ) = @_;
    return undef unless defined $logid && $logid =~ /^\d+$/;

    my $dbr = LJ::get_db_reader() or return undef;
    return $dbr->selectrow_hashref(
        'SELECT ' . join( ', ', @COLUMNS ) . ' FROM import_logs WHERE logid = ?',
        undef, $logid );
}

=head2 C<< DW::Importer::LogStore->content( $log ) >>

C<< ( $text, $missing ) >> for a log as C<logs_for> or C<log> returned it: its chunks in
order as one string of UTF-8 bytes, and how many of them could not be retrieved (typically
because the bucket expired them). A missing chunk is left out of C<$text>.

=cut

sub content {
    my ( $class, $row ) = @_;

    my ( $text, $missing ) = ( '', 0 );
    foreach my $n ( 0 .. $row->{chunks} - 1 ) {
        my $key  = _chunk_key( @{$row}{qw( userid import_data_id logid )}, $n );
        my $blob = eval { DW::BlobStore->retrieve( $NAMESPACE => $key ) };
        if ($blob) {
            $text .= $$blob;
        }
        else {
            $missing++;
        }
    }

    return ( $text, $missing );
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
