#!/usr/bin/perl
#
# DW::Importer::Scheduler
#
# Turns import items that are ready into TheSchwartz jobs.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::Scheduler;

=head1 NAME

DW::Importer::Scheduler - Queue ready import items

=head1 DESCRIPTION

This is the body of C<bin/worker/import-scheduler>: the hairy logic and
dependencies stay here so they don't have to live in TheSchwartz. Dependencies
between items are applied by L<DW::Importer::Items> as jobs finish; this module
only picks up whatever has become C<ready>.

=cut

use strict;
use warnings;

use DW::Importer::Items;
use DW::Importer::Queue;
use DW::Importer::Registry;
use TheSchwartz::Job;

=head2 C<< DW::Importer::Scheduler->recover_stale_claims( dbh => $dbh, log => $log, [ userid => $uid ] ) >>

The scheduler claims an item (C<ready> to C<queued>) before it inserts the TheSchwartz
job. If the scheduler died in between, the item is C<queued> with no job and nothing
would ever run it, or select it again, so everything waiting for it would wait forever.

This finds items that have been C<queued> for longer than
C<$LJ::IMPORTER_STALE_CLAIM_SECONDS> (default 3600) and puts the ones that have no
TheSchwartz job back to C<ready>, so the next pass schedules them. An item whose job
is still in the queue is left alone, however long it has run: a running job keeps its
row (grab_for is hours for entries and comments) and so does a job waiting to be
retried. If the queue can't be read nothing is changed. A job that finished but whose
worker died before it recorded the result is run again; imports are idempotent so that
only repeats work.

Returns the number of items put back.

=cut

sub recover_stale_claims {
    my ( $class, %opts ) = @_;
    my ( $dbh, $log ) = ( $opts{dbh}, $opts{log} || sub { } );

    my $age = $LJ::IMPORTER_STALE_CLAIM_SECONDS // 3600;
    my ( $where, @bind ) = ( "status = 'queued' AND last_touch < UNIX_TIMESTAMP() - ?", $age );
    if ( $opts{userid} ) {
        $where .= ' AND userid = ?';
        push @bind, $opts{userid};
    }
    my $rows =
        $dbh->selectall_arrayref(
        "SELECT userid, import_data_id, item, last_touch FROM import_items WHERE $where",
        undef, @bind );
    die $dbh->errstr . "\n" if $dbh->err;

    my $recovered = 0;
    foreach my $row ( @{ $rows || [] } ) {
        my ( $userid, $impid, $item, $touched ) = @$row;

        my $u = LJ::load_userid($userid) or next;
        next unless DW::Importer::Registry->item($item);

        my $jobs = DW::Importer::Queue->job_count( $u, $item, import_data_id => $impid );
        next unless defined $jobs && $jobs == 0;

        # only if nobody has touched the row since we looked
        my $reset = $dbh->do(
            q{UPDATE import_items SET status = 'ready'
              WHERE userid = ? AND import_data_id = ? AND item = ?
              AND status = 'queued' AND last_touch = ?},
            undef, $userid, $impid, $item, $touched
        );
        die $dbh->errstr . "\n" if $dbh->err;
        next unless $reset > 0;

        $log->(
            '%d:%s of user %d was queued with no job since %d, making it ready again',
            $impid, $item, $userid, $touched
        );
        $recovered++;
    }
    return $recovered;
}

=head2 C<< DW::Importer::Scheduler->run_once( %opts ) >>

Finds one user with a ready item (highest priority first) and queues all of their
ready items. Options: C<log>, a coderef called with C<sprintf> arguments,
C<userid> to only consider one user's items, and C<recover_interval>, the least number
of seconds between looks for stale claims (default 60; see C<recover_stale_claims>).

Dies if something is wrong that the caller should see.

=cut

my $last_recovery = 0;

sub run_once {
    my ( $class, %opts ) = @_;
    my $log = $opts{log} || sub { };

    LJ::start_request();

    my $dbh = LJ::get_db_writer()
        or die "no global master database handle available";

    my $interval = $opts{recover_interval} // 60;
    if ( time() - $last_recovery >= $interval ) {
        $last_recovery = time();
        $class->recover_stale_claims( dbh => $dbh, log => $log, userid => $opts{userid} );
    }

    my ( $where, @bind ) = ("status = 'ready'");
    if ( $opts{userid} ) {
        $where .= ' AND userid = ?';
        push @bind, $opts{userid};
    }
    my ( $userid, $impid ) = $dbh->selectrow_array(
        "SELECT userid, import_data_id FROM import_items WHERE $where "
            . "ORDER BY priority DESC LIMIT 1",
        undef, @bind
    );
    die $dbh->errstr . "\n" if $dbh->err;

    return $log->("nothing to do")
        unless $userid;

    my $u = LJ::load_userid($userid)
        or die "userid $userid doesn't exist\n";
    $log->( 'user %s(%d) has stuff to import', $u->user, $u->id );

    # now load up and ensure this is their most recent import group
    my $maxid =
        $dbh->selectrow_array( q{SELECT MAX(import_data_id) FROM import_items WHERE userid = ?},
        undef, $userid );
    if ( $maxid > $impid ) {
        $log->( 'user %s(%d) had stuff to import but it was aborted', $u->user, $u->id );
        $dbh->do(
            q{UPDATE import_items SET status = 'aborted'
              WHERE userid = ? AND import_data_id = ? AND status = 'ready'},
            undef, $userid, $impid
        );
        return;
    }

    my $statusrows = $dbh->selectall_arrayref(
        q{SELECT item, status, created, import_data_id, priority
          FROM import_items WHERE userid=?},
        undef, $u->id
    );
    die $dbh->errstr . "\n" if $dbh->err;
    die "user had no status rows!\n" unless @{ $statusrows || [] };

    my @status = (
        map {
            {
                item     => $_->[0],
                status   => $_->[1],
                created  => $_->[2],
                impid    => $_->[3],
                priority => $_->[4]
            }
        } @$statusrows
    );

    # FIXME: handle the case where the user already has an import_job going and it's
    # different from the current import_data_id that we are trying to import for.
    # if we don't handle this case, we're going to get pretty confused about what
    # to update later...

    # now find the ready jobs, dispatch them
    foreach my $item (@status) {

        next if $item->{status} ne 'ready';

        $log->( 'scheduling %d:%s', $item->{impid}, $item->{item} );

        my $class =
            ( DW::Importer::Registry->item( $item->{item} ) || die 'unknown item ' )->{class};

        my $sh = LJ::theschwartz()
            or die "no schwartz client\n";

        my $job = TheSchwartz::Job->new(
            funcname => $class,
            uniqkey  => join( '-', ( $item->{item}, $u->id ) ),
            arg      => {
                userid         => $u->id,
                import_data_id => $item->{impid},
            }
        ) or die "can't create job\n";

        # Claim the row before inserting the job. Only one scheduler can move it out of
        # 'ready', so a competing scheduler skips it here instead of clashing on the
        # insert, and the job cannot finish (and set 'succeeded') before we mark it.
        my $claimed = $dbh->do(
            q{UPDATE import_items SET status = 'queued', last_touch = UNIX_TIMESTAMP()
                  WHERE userid = ? AND import_data_id = ? AND item = ? AND status = 'ready'},
            undef, $u->id, $item->{impid}, $item->{item}
        );
        die $dbh->errstr . "\n" if $dbh->err;
        unless ( $claimed > 0 ) {
            $log->( '%d:%s was claimed by another scheduler', $item->{impid}, $item->{item} );
            next;
        }

        my $h            = eval { $sh->insert($job) };
        my $insert_error = $@;
        unless ($h) {

            # best guess is that this is a dupe, so abort it, along with whatever was
            # waiting for it, which can no longer run. (an insert that throws is treated
            # the same: leaving the row queued would strand it, as nothing selects it.)
            if ($insert_error) {
                $insert_error =~ s/\s+\z//;
                $log->( 'inserting the job for %s failed: %s', $item->{item}, $insert_error );
            }
            $log->( 'looks like they already have %s queued, aborting this one', $item->{item} );
            $dbh->do(
                q{UPDATE import_items SET status = 'aborted'
                      WHERE userid = ? AND import_data_id = ? AND item = ? AND status = 'queued'},
                undef, $u->id, $item->{impid}, $item->{item}
            );
            die $dbh->errstr . "\n" if $dbh->err;
            DW::Importer::Items->advance( $u, $item->{impid}, $item->{item}, 'failure' );
            return;
        }

        $u->set_prop( import_job => $item->{impid} );
    }
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
