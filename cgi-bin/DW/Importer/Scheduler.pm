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
use DW::Importer::Registry;
use TheSchwartz::Job;

=head2 C<< DW::Importer::Scheduler->run_once( %opts ) >>

Finds one user with a ready item (highest priority first) and queues all of their
ready items. Options: C<log>, a coderef called with C<sprintf> arguments, and
C<userid> to only consider one user's items.

Dies if something is wrong that the caller should see.

=cut

sub run_once {
    my ( $class, %opts ) = @_;
    my $log = $opts{log} || sub { };

    LJ::start_request();

    my $dbh = LJ::get_db_writer()
        or die "no global master database handle available";

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

        my $h = $sh->insert($job);
        unless ($h) {

            # best guess is that this is a dupe, so abort it, along with whatever was
            # waiting for it, which can no longer run
            $log->( 'looks like they already have %s queued, aborting this one', $item->{item} );
            my $aborted = $dbh->do(
                q{UPDATE import_items SET status = 'aborted'
                      WHERE userid = ? AND import_data_id = ? AND item = ? AND status = 'ready'},
                undef, $u->id, $item->{impid}, $item->{item}
            );
            die $dbh->errstr . "\n" if $dbh->err;

            # Another scheduler may have queued this same item between our read and our
            # insert. The row is then no longer 'ready', nothing was aborted here, and its
            # dependents must keep waiting for that job.
            DW::Importer::Items->advance( $u, $item->{impid}, $item->{item}, 'failure' )
                if $aborted > 0;
            return;
        }

        $u->set_prop( import_job => $item->{impid} );

        $dbh->do(
            "UPDATE import_items SET status = 'queued', last_touch = UNIX_TIMESTAMP() "
                . "WHERE userid = ? AND item = ? AND import_data_id = ?",
            undef, $u->id, $item->{item}, $item->{impid}
        );
        die $dbh->errstr . "\n" if $dbh->err;
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
