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
