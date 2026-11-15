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

Calls C<$code> with a handle for each TheSchwartz database. Returns how many databases
were reachable. The driver owns the handle, so it is kept alive while the callback runs.

=cut

sub each_dbh {
    my ( $class, $code ) = @_;

    my $client = LJ::theschwartz()
        or return 0;

    my $reached = 0;
    foreach my $hashdsn ( $client->shuffled_databases ) {
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
    return $reached;
}

=head2 C<< DW::Importer::Queue->job_count( $u, $item, [ import_data_id => $id ] ) >>

How many TheSchwartz jobs exist for this item of this user: jobs of the item's worker
class with the uniqkey the scheduler gives it (C<item-userid>). With C<import_data_id>,
only jobs for that import count. A job stays in the table while it runs and while it
waits to be retried, and is removed when it completes.

Returns undef, not 0, if the queue could not be read, so that callers don't mistake
"don't know" for "no job".

=cut

sub job_count {
    my ( $class, $u, $item, %opts ) = @_;

    my $def = DW::Importer::Registry->item($item)
        or return undef;
    my $uniqkey = join( '-', $item, $u->id );

    my $count   = 0;
    my $reached = $class->each_dbh(
        sub {
            my ($dbh)    = @_;
            my ($funcid) = $dbh->selectrow_array( 'SELECT funcid FROM funcmap WHERE funcname = ?',
                undef, $def->{class} );
            return unless $funcid;

            my $rows =
                $dbh->selectall_arrayref( 'SELECT arg FROM job WHERE funcid = ? AND uniqkey = ?',
                undef, $funcid, $uniqkey )
                || [];
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
    return $reached ? $count : undef;
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
