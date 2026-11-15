#!/usr/bin/perl
#
# DW::Importer::Control
#
# Cancels an import, and reruns the items of one that went wrong.
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

package DW::Importer::Control;

=head1 NAME

DW::Importer::Control - Cancel an import or rerun its items

=head1 DESCRIPTION

The operations an administrator has on a user's import, made safe to do while workers
and the scheduler are running: every change to an item is an C<UPDATE> conditional on the
status that was read, so something that happened in between is not undone.

=over

=item *

C<cancel> puts the items that have not finished into C<aborted> and takes their jobs out
of the queue. The job runner (L<DW::Importer::Job>) treats C<aborted> as "do nothing more"
for a job that is already running.

=item *

C<retry> puts failed or aborted items (and what depended on them) back to C<init>, and
releases the ones that can start to C<ready>, where the scheduler picks them up as it
does for a new import.

=back

=cut

use strict;
use warnings;

use DW::Importer::Items;
use DW::Importer::Queue;
use DW::Importer::Registry;

# the statuses an item can be cancelled from
my @CANCELLABLE = qw( init ready queued );

# the statuses an item can be rerun from, when it is named
my @RERUNNABLE = qw( succeeded failed aborted );

# the statuses retry resets when it works out what to rerun
my @RESETTABLE = qw( failed aborted );

=head2 C<< DW::Importer::Control->cancel( $u, $import_data_id, actor => $actor ) >>

Cancels the import: every item in C<init>, C<ready> or C<queued> becomes C<aborted>, and
the import's TheSchwartz jobs that nothing is working on are removed. A job that is
running is left to finish, and records nothing when it does.

The items go first, so that a job a worker grabs in the meantime sees the cancel.
C<$actor> is the user who did it, for the status history.

Returns a hashref: C<aborted> (the items changed), C<jobs_removed>, C<jobs_running> and
C<queue_complete>, which is false if the queue could not be read in full, so some job may
be left.

=cut

sub cancel {
    my ( $class, $u, $import_data_id, %opts ) = @_;
    my $actor = $opts{actor} or die "cancel needs an actor\n";

    my $dbh = LJ::get_db_writer()
        or die "no global master database handle available\n";

    my $status = $class->_statuses( $dbh, $u, $import_data_id );
    my @aborted;
    foreach my $item ( sort keys %$status ) {
        next unless grep { $status->{$item} eq $_ } @CANCELLABLE;
        push @aborted, $item
            if $class->_move( $dbh, $u, $import_data_id, $item, $status->{$item}, 'aborted' );
    }

    my $jobs = DW::Importer::Queue->remove_idle_jobs( $u, $import_data_id );

    my %result = (
        aborted        => \@aborted,
        jobs_removed   => $jobs->{removed},
        jobs_running   => $jobs->{running},
        queue_complete => $jobs->{complete},
    );

    LJ::statushistory_add(
        $u->id,
        $actor->id,
        'import_cancel',
        sprintf(
            'import %d: aborted %d items (%s), removed %d jobs, %d running%s',
            $import_data_id, scalar @aborted,
            join( ' ', @aborted ), $result{jobs_removed},
            $result{jobs_running}, $result{queue_complete} ? '' : ', queue not fully read'
        )
    );

    return \%result;
}

=head2 C<< DW::Importer::Control->retry_refusal( $u, $import_data_id ) >>

Why this import can't be retried now, or undef if it can. Retrying is only for the user's
latest import, because the scheduler abandons older ones, and only when nothing is in
flight, so that a rerun can't overlap a job that is still going. The reasons are
C<notlatest> and C<inflight> (an item is C<ready> or C<queued>).

=cut

sub retry_refusal {
    my ( $class, $u, $import_data_id ) = @_;

    my $dbh = LJ::get_db_writer()
        or die "no global master database handle available\n";

    # the same definition of "latest" the scheduler uses
    my $latest =
        $dbh->selectrow_array( 'SELECT MAX(import_data_id) FROM import_items WHERE userid = ?',
        undef, $u->id );
    return 'notlatest' unless defined $latest && $latest == $import_data_id;

    my $status = $class->_statuses( $dbh, $u, $import_data_id );
    return 'inflight' if grep { $_ eq 'ready' || $_ eq 'queued' } values %$status;

    return undef;
}

=head2 C<< DW::Importer::Control->retry( $u, $import_data_id, actor => $actor, [ items => \@items ] ) >>

Reruns items of the import. By default that is every C<failed> or C<aborted> item;
C<items> names the ones to rerun instead, in any finished state, so a succeeded item can be
run again. Whatever is C<failed> or C<aborted> and depends on a rerun item, however
indirectly, is reset too, since it never ran or ran on what is being replaced.

The reset items go to C<init>, and the ones whose dependencies in this import have all
succeeded become C<ready>. Items that depend on something that is still failed stay
C<init> (C<waiting>); rerun that first.

Nothing is changed, and C<< { error => $code } >> is returned, if the import can't be
retried (see C<retry_refusal>), if a job for one of its items is still in the queue
(C<jobsexist>: a cancelled job that is still running, say) or the queue could not be read
(C<queueunknown>), or if there is nothing to rerun (C<nothing>).

Otherwise returns a hashref of the C<reset>, C<ready> and C<waiting> item names.

=cut

sub retry {
    my ( $class, $u, $import_data_id, %opts ) = @_;
    my $actor = $opts{actor} or die "retry needs an actor\n";

    my $dbh = LJ::get_db_writer()
        or die "no global master database handle available\n";

    my $refusal = $class->retry_refusal( $u, $import_data_id );
    return { error => $refusal } if $refusal;

    # a job still in the queue would collide with the one the scheduler makes for the rerun
    my ( $jobs, $complete ) = DW::Importer::Queue->jobs_for_import( $u, $import_data_id );
    return { error => 'jobsexist' } if %$jobs;
    return { error => 'queueunknown' } unless $complete;

    my $status      = $class->_statuses( $dbh, $u, $import_data_id );
    my $journaltype = DW::Importer::Registry->journaltype($u);

    my @rerun;
    if ( $opts{items} ) {
        my %want = map { $_ => 1 } @{ $opts{items} };
        foreach my $item ( sort keys %want ) {
            my $current = $status->{$item} or next;
            push @rerun, $item if grep { $current eq $_ } @RERUNNABLE;
        }
    }
    else {
        @rerun = grep {
            my $s = $status->{$_};
            grep { $s eq $_ } @RESETTABLE
        } sort keys %$status;
    }
    @rerun = grep { DW::Importer::Registry->item($_) } @rerun;
    return { error => 'nothing' } unless @rerun;

    # what depends on a rerun item and is stuck behind a failure or an abort goes back too
    my %reset = map { $_ => 1 } @rerun;
    my @todo  = @rerun;
    while ( defined( my $item = shift @todo ) ) {
        foreach my $dep ( DW::Importer::Registry->dependents( $item, $journaltype ) ) {
            next if $reset{$dep} || !$status->{$dep};
            next unless grep { $status->{$dep} eq $_ } @RESETTABLE;
            $reset{$dep} = 1;
            push @todo, $dep;
        }
    }

    my @reset;
    foreach my $item ( sort keys %reset ) {
        push @reset, $item
            if $class->_move( $dbh, $u, $import_data_id, $item, $status->{$item}, 'init' );
    }

    my $released = DW::Importer::Items->release( $u, $import_data_id, \@reset );

    my %result = (
        reset   => \@reset,
        ready   => $released->{ready},
        waiting => $released->{waiting},
    );

    LJ::statushistory_add(
        $u->id,
        $actor->id,
        'import_retry',
        sprintf(
            'import %d: reset %d items (%s), %d ready',
            $import_data_id,
            scalar @reset,
            join( ' ', @reset ),
            scalar @{ $result{ready} }
        )
    );

    return \%result;
}

# the status of each item of the import, by name
sub _statuses {
    my ( $class, $dbh, $u, $import_data_id ) = @_;

    my $rows = $dbh->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $import_data_id );
    die $dbh->errstr . "\n" if $dbh->err;

    return { map { $_->[0] => $_->[1] } @$rows };
}

# Changes an item's status, but only if it is still what we read, so whatever a worker or
# the scheduler did meanwhile wins. Returns true if the item was changed.
sub _move {
    my ( $class, $dbh, $u, $import_data_id, $item, $from, $to ) = @_;

    my $changed = $dbh->do(
        'UPDATE import_items SET status = ?, last_touch = UNIX_TIMESTAMP() '
            . 'WHERE userid = ? AND import_data_id = ? AND item = ? AND status = ?',
        undef, $to, $u->id, $import_data_id, $item, $from
    );
    die $dbh->errstr . "\n" if $dbh->err;

    return $changed && $changed > 0;    # ('0E0' is a true string)
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
