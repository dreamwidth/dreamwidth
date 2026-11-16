#!/usr/bin/perl
#
# DW::Importer::Queue
#
# Looks at the TheSchwartz queue on behalf of the importer.
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

package DW::Importer::Queue;

=head1 NAME

DW::Importer::Queue - Read access to the importer's TheSchwartz jobs

=head1 DESCRIPTION

The one place that opens the TheSchwartz databases for the importer, through the shared
C<LJ::theschwartz> client so that anything configured (or faked, under
C<$LJ::_T_FAKESCHWARTZ>) for it applies here too.

=cut

use strict;
use warnings;

use Log::Log4perl;
use Storable ();

use DW::Importer::Registry;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

=head2 C<< DW::Importer::Queue->each_dbh( $code ) >>

Calls C<$code> with a handle for each TheSchwartz database that can be reached. Returns
how many were. The driver owns the handle, so it is kept alive while the callback runs.
See C<all_dbhs> for when every database matters.

=cut

sub each_dbh {
    my ( $class, $code ) = @_;
    my ($reached) = $class->all_dbhs($code);
    return $reached;
}

=head2 C<< DW::Importer::Queue->all_dbhs( $code ) >>

Like C<each_dbh>, and returns C<( $reached, $configured )>: how many databases were
connected to and how many there are. Something that wants to know a job does not exist
has to see every database, so it needs both.

=cut

sub all_dbhs {
    my ( $class, $code ) = @_;

    my $client = LJ::theschwartz()
        or return ( 0, 0 );

    my @databases = $client->shuffled_databases;
    my $reached   = 0;
    foreach my $hashdsn (@databases) {
        my $driver = eval            { $client->driver_for($hashdsn) };
        my $dbh    = $driver && eval { $driver->rw_handle };
        unless ($dbh) {
            $log->error(
                'Unable to connect to a TheSchwartz database: ' . ( $@ || 'unknown error' ) );
            next;
        }

        $reached++;
        $code->($dbh);
    }
    return ( $reached, scalar @databases );
}

=head2 C<< DW::Importer::Queue->job_count( $u, $item, [ import_data_id => $id ] ) >>

How many TheSchwartz jobs exist for this item of this user: jobs of the item's worker
class with the uniqkey the scheduler gives it (C<item-userid>). With C<import_data_id>,
only jobs for that import count. A job stays in the table while it runs and while it
waits to be retried, and is removed when it completes.

Returns undef, not 0, unless the answer is known. A job that was seen is a count even if
something else could not be read, but "no job" needs every configured queue database to
have been connected to and every query on them to have succeeded: a running job could be
in the one that wasn't. A function name that is not in a database's C<funcmap> does mean
there are no jobs of it there.

=cut

sub job_count {
    my ( $class, $u, $item, %opts ) = @_;

    my $def = DW::Importer::Registry->item($item)
        or return undef;
    my $uniqkey = join( '-', $item, $u->id );

    my ( $count, $failed ) = ( 0, 0 );
    my ( $reached, $configured ) = $class->all_dbhs(
        sub {
            my ($dbh) = @_;

            my $funcs = eval {
                $dbh->selectall_arrayref( 'SELECT funcid FROM funcmap WHERE funcname = ?',
                    undef, $def->{class} );
            };
            unless ( $funcs && !$dbh->err ) {
                $log->error( 'Unable to read a TheSchwartz funcmap: ' . ( $@ || $dbh->errstr ) );
                $failed++;
                return;
            }
            return unless @$funcs;    # it has never had a job of this kind
            my $funcid = $funcs->[0]->[0];

            my $rows = eval {
                $dbh->selectall_arrayref( 'SELECT arg FROM job WHERE funcid = ? AND uniqkey = ?',
                    undef, $funcid, $uniqkey );
            };
            unless ( $rows && !$dbh->err ) {
                $log->error( 'Unable to read TheSchwartz jobs: ' . ( $@ || $dbh->errstr ) );
                $failed++;
                return;
            }

            foreach my $row (@$rows) {
                if ( defined $opts{import_data_id} ) {
                    my $arg = eval { Storable::thaw( $row->[0] ) };
                    next
                        unless ref $arg eq 'HASH'
                        && defined $arg->{import_data_id}
                        && $arg->{import_data_id} == $opts{import_data_id};
                }
                $count++;
            }
        }
    );

    return $count if $count;
    return undef  if $failed || !$configured || $reached < $configured;
    return 0;
}

# Calls $code->( $dbh, $item_name, $job_row ) for each job of an import: a job of an item's
# worker class, with the uniqkey the scheduler gives it, whose arg names this import. $job_row
# is a hashref of the job table's columns. Returns ( $complete ), which is true only if every
# configured database was read without error, since a job that wasn't seen could be in one that
# wasn't.
sub _each_import_job {
    my ( $class, $u, $import_data_id, $code ) = @_;

    my $failed = 0;
    my ( $reached, $configured ) = $class->all_dbhs(
        sub {
            my ($dbh) = @_;

            my $funcs = eval { $dbh->selectall_arrayref('SELECT funcid, funcname FROM funcmap') };
            unless ( $funcs && !$dbh->err ) {
                $log->error( 'Unable to read a TheSchwartz funcmap: ' . ( $@ || $dbh->errstr ) );
                $failed++;
                return;
            }

            my %item_of_func;
            foreach my $func (@$funcs) {
                my $item = DW::Importer::Registry->item_for_class( $func->[1] ) or next;
                $item_of_func{ $func->[0] } = $item->{name};
            }
            return unless %item_of_func;

            my @funcids = sort { $a <=> $b } keys %item_of_func;
            my $rows    = eval {
                $dbh->selectall_arrayref(
                    'SELECT jobid, funcid, arg, uniqkey, insert_time, run_after, grabbed_until '
                        . 'FROM job WHERE funcid IN ('
                        . join( ',', map { '?' } @funcids ) . ')',
                    { Slice => {} },
                    @funcids
                );
            };
            unless ( $rows && !$dbh->err ) {
                $log->error( 'Unable to read TheSchwartz jobs: ' . ( $@ || $dbh->errstr ) );
                $failed++;
                return;
            }

            foreach my $row (@$rows) {
                my $item = $item_of_func{ $row->{funcid} };
                next unless ( $row->{uniqkey} // '' ) eq join( '-', $item, $u->id );

                my $arg = eval { Storable::thaw( $row->{arg} ) };
                next
                    unless ref $arg eq 'HASH'
                    && defined $arg->{import_data_id}
                    && $arg->{import_data_id} == $import_data_id;

                $code->( $dbh, $item, $row );
            }
        }
    );

    return !$failed && $configured && $reached == $configured ? 1 : 0;
}

=head2 C<< DW::Importer::Queue->jobs_for_import( $u, $import_data_id ) >>

The TheSchwartz jobs that exist for the items of one import, for showing to an
administrator. Returns C<( \%jobs, $complete )>: C<%jobs> maps an item's name to an
arrayref of its jobs (there should be at most one), each a hashref of C<jobid>,
C<insert_time>, C<run_after>, C<grabbed_until>, C<running> (it is being worked on now),
C<failures> (how many failures TheSchwartz has recorded for it) and C<errors> (the last few
messages, newest first). C<$complete> is false if some queue database could not be read,
in which case a job may be missing from the answer.

=cut

sub jobs_for_import {
    my ( $class, $u, $import_data_id ) = @_;

    my %jobs;
    my $now      = time();
    my $complete = $class->_each_import_job(
        $u,
        $import_data_id,
        sub {
            my ( $dbh, $item, $row ) = @_;

            my %job = map { $_ => $row->{$_} } qw( jobid insert_time run_after grabbed_until );
            $job{running} = $row->{grabbed_until} > $now ? 1 : 0;

            # the details are not worth failing over; the page shows what it has
            my $failures = eval {
                $dbh->selectrow_array( 'SELECT COUNT(*) FROM error WHERE jobid = ?',
                    undef, $row->{jobid} );
            };
            my $errors = eval {
                $dbh->selectcol_arrayref(
                    'SELECT message FROM error WHERE jobid = ? ORDER BY error_time DESC LIMIT 3',
                    undef, $row->{jobid} );
            };
            $job{failures} = $failures || 0;
            $job{errors}   = $errors   || [];

            push @{ $jobs{$item} }, \%job;
        }
    );

    return ( \%jobs, $complete );
}

=head2 C<< DW::Importer::Queue->remove_idle_jobs( $u, $import_data_id ) >>

Removes the import's jobs that no worker has grabbed, so they never run. A job that is
being worked on (C<grabbed_until> in the future) is left in place for its worker to finish,
and each job is deleted only if it is still idle at that moment, so a worker that grabs
one meanwhile is not cut off. Returns a hashref of how many jobs were C<removed> and how
many were left C<running>; C<errors> counts deletes that failed, and C<complete> is false
if some queue database could not be read or a delete failed.

=cut

sub remove_idle_jobs {
    my ( $class, $u, $import_data_id ) = @_;

    my %result = ( removed => 0, running => 0, errors => 0 );
    my $now    = time();
    $result{complete} = $class->_each_import_job(
        $u,
        $import_data_id,
        sub {
            my ( $dbh, $item, $row ) = @_;

            my $deleted = eval {
                $dbh->do( 'DELETE FROM job WHERE jobid = ? AND grabbed_until <= ?',
                    undef, $row->{jobid}, $now );
            };
            if ( $dbh->err || !defined $deleted ) {
                $log->error( 'Unable to remove a TheSchwartz job: ' . ( $@ || $dbh->errstr ) );
                $result{errors}++;
            }
            elsif ( $deleted > 0 ) {
                $result{removed}++;
            }
            else {
                $result{running}++;
            }
        }
    );

    $result{complete} = 0 if $result{errors};

    return \%result;
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
