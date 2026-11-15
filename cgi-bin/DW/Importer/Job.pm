#!/usr/bin/perl
#
# DW::Importer::Job
#
# Base class for the TheSchwartz workers that run import items.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::Job;

=head1 NAME

DW::Importer::Job - Runs one item of an import as a TheSchwartz job

=head1 SYNOPSIS

    package My::Importer::Thing;
    use base 'DW::Importer::Job';

    sub run {
        my ( $class, $ctx ) = @_;

        my $r = fetch_something( $ctx->data );
        return $ctx->temp_fail( 'Fetch failed: %s', $r->{error} ) if $r->{error};

        save_it( $ctx->u, $r );
        return $ctx->ok;
    }

=head1 DESCRIPTION

A worker class (the item's C<class> in L<DW::Importer::Registry>) inherits from this
and implements only C<run>. C<work>, which TheSchwartz calls, does everything around
it:

=over

=item *

loads the import and the user, and declines the job if importing from the source is
switched off;

=item *

builds the L<DW::Importer::Context> and its logger, and sets the process title;

=item *

calls C<run> and turns what it returns (or dies with) into an
L<DW::Importer::Outcome>: an exception that is not an outcome is a temporary failure;

=item *

records the outcome: the item's status in C<import_items>, the notification to the
user (to every maintainer, for a community), stats, the TheSchwartz job state, the
escalation of a temporary failure to a permanent one after C<max_retries>, and the
chaining that readies or aborts the items waiting for this one
(L<DW::Importer::Items>).

=back

=cut

use strict;
use warnings;
use v5.10;

use Carp qw/ croak /;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Storable;
use Time::HiRes qw/ time /;

use DW::Importer::Context;
use DW::Importer::Items;
use DW::Importer::Logger;
use DW::Importer::Outcome;
use DW::Importer::Registry;
use DW::Importer::Sink::Live;
use DW::Stats;

use base 'TheSchwartz::Worker';

=head1 Writing a job

=head2 C<< $class->run( $ctx ) >>

Does the work. Return an L<DW::Importer::Outcome> (C<< $ctx->ok >>, C<< $ctx->fail(...) >>,
C<< $ctx->temp_fail(...) >>), or die with one. Returning anything else is a success.

=cut

sub run {
    my ($class) = @_;
    croak "$class must implement run";
}

=head2 C<< $class->exit_after_job >>

True if the worker process should exit once the job is done, to give back memory the
job is known to leak. The shared worker scripts honour it through C<exit_requested>;
C<work> itself never exits.

=cut

sub exit_after_job { 0 }

=head2 C<< DW::Importer::Job->exit_requested >>

True if a job that has run in this process asked for the process to exit.

=head2 C<< DW::Importer::Job->reset_exit_request >>

Clears that request.

=cut

my $EXIT_REQUESTED = 0;
sub exit_requested     { $EXIT_REQUESTED }
sub reset_exit_request { $EXIT_REQUESTED = 0 }

=head2 C<< $class->logger_for( %args ) >>

Makes the logger for a job (C<job>, C<userid>, C<import_data_id>, C<item>). Override it
to log somewhere else, such as in memory.

=cut

sub logger_for {
    my ( $class, %args ) = @_;
    return DW::Importer::Logger->for_job(%args);
}

=head2 C<< $class->transport_for( $data ) >>

The object the job's source adapter does its network I/O through. Returns undef, so the
adapter's own default is used; a source's worker base class overrides it. Setting
C<$DW::Importer::Job::TRANSPORT> (with C<local>) replaces it for every job, which is how
tests replay a canned site through the real workers.

=cut

our $TRANSPORT;

sub transport_for { return undef }

=head2 C<< $class->on_exception( $ctx, $message ) >>

Called when C<run> dies with something other than an outcome, before the job is
treated as a temporary failure. Does nothing; jobs may override it to keep more
information.

=cut

sub on_exception { }

=head1 Running a job

=head2 C<< $class->work( $job ) >>

The entry point TheSchwartz calls.

=cut

sub work {
    my ( $class, $job ) = @_;

    LJ::start_request();

    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );
    my $item = DW::Importer::Registry->item_for_class($class);

    unless ( $data && $item ) {
        $job->permanent_failure(
            $data
            ? "$class is not a registered importer item."
            : "Import $opts->{import_data_id} for user $opts->{userid} not found."
        );
        return;
    }

    return $class->decline($job) unless $class->enabled($data);

    my $ctx = DW::Importer::Context->new(
        class     => $class,
        job       => $job,
        data      => $data,
        item      => $item,
        u         => LJ::load_userid( $data->{userid} ),
        transport => $TRANSPORT || $class->transport_for($data),
        logger    => $class->logger_for(
            job            => $job,
            userid         => $data->{userid},
            import_data_id => $data->{import_data_id},
            item           => $item->{name},
        ),
    );

    $ctx->{sink} = DW::Importer::Sink::Live->new( u => $ctx->u, data => $data );

    my $outcome = $class->_execute($ctx);
    $class->_record( $ctx, $outcome );

    $ctx->logger->close if $ctx->logger;
    $EXIT_REQUESTED = 1 if $class->exit_after_job;

    return;
}

# runs the job, always producing an outcome
sub _execute {
    my ( $class, $ctx ) = @_;

    my $outcome;
    my $ok = eval {
        my $u = $ctx->u
            or die DW::Importer::Outcome->fail( 'Unable to load target with id %d.',
            $ctx->data->{userid} );

        $ctx->title;
        $ctx->log( 'Import begun for %s(%d).', $u->user, $u->userid );

        $outcome = $class->run($ctx);
        1;
    };

    unless ($ok) {
        my $err = $@;
        if ( ref $err && eval { $err->isa('DW::Importer::Outcome') } ) {
            $outcome = $err;
        }
        else {
            ( my $msg = "$err" ) =~ s/\r?\n/ /gs;
            $ctx->log( 'ERROR: %s', $msg );
            $class->on_exception( $ctx, $msg );
            $outcome = DW::Importer::Outcome->temp_fail( 'Failure running job: %s', $msg );
        }
    }

    return $outcome if ref $outcome && eval { $outcome->isa('DW::Importer::Outcome') };
    return DW::Importer::Outcome->ok;
}

# applies the outcome to the item, the user and the TheSchwartz job
sub _record {
    my ( $class, $ctx, $outcome ) = @_;

    my ( $data, $item, $job ) = ( $ctx->data, $ctx->item->{name}, $ctx->job );
    my $status = $outcome->status;

    if ( $status eq 'ok' ) {
        my $show = $outcome->show // $ctx->item->{notify_on_success};
        $class->ok( $data, $item, $job, $show ? 1 : 0 );
    }
    elsif ( $status eq 'temp_fail' ) {
        $class->temp_fail( $data, $item, $job, $outcome->message );
    }
    else {
        $class->fail( $data, $item, $job, $outcome->message );
    }
}

=head1 Outcome handling

These are what C<work> uses to record an outcome; jobs return outcomes instead of
calling them. All take the C<import_data> row, the item name and the TheSchwartz job.

=head2 C<< $class->import_data( $userid, $import_data_id ) >>

Returns the C<import_data> row as a hashref, with C<options> thawed, or undef.

=cut

sub import_data {
    my ( $class, $userid, $impid ) = @_;

    my $dbh = LJ::get_db_writer()
        or croak 'unable to get global database master';
    my $hr = $dbh->selectrow_hashref(
        'SELECT userid, hostname, username, usejournal, password_md5, import_data_id, options '
            . 'FROM import_data WHERE userid = ? AND import_data_id = ?',
        undef, $userid, $impid
    );
    croak $dbh->errstr if $dbh->err;

    $hr->{options} = Storable::thaw( $hr->{options} ) || {}
        if $hr && $hr->{options};

    return $hr;
}

=head2 C<< $class->userids_to_message( $userid ) >>

For communities, this returns the userids for all of the admins so we let them know what has
happened with their import.

=cut

sub userids_to_message {
    my ( $class, $uid ) = @_;

    my $u = LJ::load_userid($uid)
        or return $uid;    # fail?
    return $uid unless $u->is_community;

    return $u->maintainer_userids;
}

=head2 C<< $class->_should_exit( $message ) >>

Determine whether or not this failure message should be considered to be more than just a
job failure. I.e., whether we should exit the worker to try to get a new IP.

=cut

sub _should_exit {
    my ( $class, $message ) = @_;

    return 1 if $message =~ /Failed to connect to the server/i;

    return 0;
}

=head2 C<< $class->_format_message( "text", [arguments, ...] ) >>

Builds a failure message. With arguments the text is a C<sprintf> format; without, it is
used as is, because callers pass error strings from remote sites that may contain C<%>.

=cut

sub _format_message {
    my ( $class, $msgt, @args ) = @_;
    return @args ? sprintf( $msgt, @args ) : $msgt;
}

=head2 C<< $class->_advance( $import_data, $item, $outcome ) >>

Applies the dependency rules in L<DW::Importer::Registry> now that an item has finished
(C<$outcome> is C<success> or C<failure>).

=cut

sub _advance {
    my ( $class, $imp, $item, $outcome ) = @_;

    my $u = LJ::load_userid( $imp->{userid} )
        or return;
    DW::Importer::Items->advance( $u, $imp->{import_data_id}, $item, $outcome );
}

=head2 C<< $class->fail( $import_data, $item, $job, "text", [arguments, ...] ) >>

Permanently fail this import job.

=cut

sub fail {
    my ( $class, $imp, $item, $job, $msgt, @args ) = @_;
    $0 = 'content-importer [bored]';

    # clear "request" cache of db handles to force revalidation in case one we need now
    # has been idle during a long import
    $LJ::DBIRole->clear_req_cache();

    if ( my $dbh = LJ::get_db_writer() ) {
        $dbh->do(
            "UPDATE import_items SET status = 'failed', last_touch = UNIX_TIMESTAMP() "
                . "WHERE userid = ? AND item = ? AND import_data_id = ?",
            undef, $imp->{userid}, $item, $imp->{import_data_id}
        );
        warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
    }

    # whatever was waiting for this item can never run now
    $class->_advance( $imp, $item, 'failure' );

    my $msg = $class->_format_message( $msgt, @args );
    warn "Permanent failure: $msg\n"
        if $LJ::IS_DEV_SERVER;

    DW::Stats::increment( 'dw.worker.importer.job_completed',
        1, [ "item:$item", "result:fail", "hostname:" . ( $imp->{hostname} || 'unknown' ) ] );

    # fire an event for the user to know that it failed
    foreach my $uid ( $class->userids_to_message( $imp->{userid} ) ) {
        LJ::Event::ImportStatus->new( $uid, $item, { type => 'fail', msg => $msg } )->fire;
    }

    $job->permanent_failure($msg);

    if ( $class->_should_exit($msg) ) {
        $log->fatal('Important failure: exiting worker.');
        open FILE, '>', "$LJ::VAR/$$.please_die" or exit 2;
        close FILE;
    }

    return;
}

=head2 C<< $class->temp_fail( $import_data, $item, $job, "text", [arguments, ...] ) >>

Temporarily fail this import job, it will get retried if it hasn't failed too many times.

=cut

sub temp_fail {
    my ( $class, $imp, $item, $job, $msgt, @args ) = @_;
    $0 = 'content-importer [bored]';

    # clear "request" cache of db handles to force revalidation in case one we need now
    # has been idle during a long import
    $LJ::DBIRole->clear_req_cache();

    # Check if we are out of failures
    my $max_fails = $class->max_retries;
    my $this_fail = $job->failures + 1;    # Add this failure on.
    return $class->fail( $imp, $item, $job, $msgt, @args ) if $this_fail >= $max_fails;

    my $msg = $class->_format_message( $msgt, @args );
    warn "Temporary failure: $msg\n"
        if $LJ::IS_DEV_SERVER;

    DW::Stats::increment( 'dw.worker.importer.job_completed',
        1, [ "item:$item", "result:temp_fail", "hostname:" . ( $imp->{hostname} || 'unknown' ) ] );

    # fire an event for the user to know that it failed (temporarily)
    foreach my $uid ( $class->userids_to_message( $imp->{userid} ) ) {
        LJ::Event::ImportStatus->new(
            $uid, $item,
            {
                type     => 'temp_fail',
                msg      => $msg,
                failures => $job->failures,
                retries  => $job->funcname->max_retries,
            }
        )->fire;
    }

    $job->failed($msg);

    if ( $class->_should_exit($msg) ) {
        $log->fatal('Important failure: exiting worker.');
        open FILE, '>', "$LJ::VAR/$$.please_die" or exit 2;
        close FILE;
    }

    return;
}

=head2 C<< $class->ok( $import_data, $item, $job, $show ) >>

Successfully end this import job. The user is told unless C<$show> is defined and 0.

=cut

sub ok {
    my ( $class, $imp, $item, $job, $show ) = @_;
    $0 = 'content-importer [bored]';

    # clear "request" cache of db handles to force revalidation in case one we need now
    # has been idle during a long import
    $LJ::DBIRole->clear_req_cache();

    if ( my $dbh = LJ::get_db_writer() ) {
        $dbh->do(
            "UPDATE import_items SET status = 'succeeded', last_touch = UNIX_TIMESTAMP() "
                . "WHERE userid = ? AND item = ? AND import_data_id = ?",
            undef, $imp->{userid}, $item, $imp->{import_data_id}
        );
        warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
    }

    # start whatever was waiting for this item
    $class->_advance( $imp, $item, 'success' );

    DW::Stats::increment( 'dw.worker.importer.job_completed',
        1, [ "item:$item", "result:ok", "hostname:" . ( $imp->{hostname} || 'unknown' ) ] );

    # advise the user this finished
    unless ( defined $show && $show == 0 ) {
        foreach my $uid ( $class->userids_to_message( $imp->{userid} ) ) {
            LJ::Event::ImportStatus->new( $uid, $item, { type => 'ok' } )->fire;
        }
    }

    $job->completed;
    return;
}

=head2 C<< $class->decline( $job, %opts ) >>

Decline to process the job for now. Will retry again later. (Does not count against the maximum number of retries)

=cut

sub decline {
    my ( $class, $job, %opts ) = @_;

    DW::Stats::increment( 'dw.worker.importer.job_completed', 1, ['result:decline'] );

    $opts{delay} ||= 3600 * 24;
    $job->run_after( time() + $opts{delay} );
    $job->declined(1);
    $job->save();

    return;
}

=head2 C<< $class->enabled( $data ) >>

Check whether this import source is enabled.

=cut

sub enabled {
    my ( $class, $data ) = @_;

    my $item = DW::Importer::Registry->item_for_class($class);
    return DW::Importer::Registry->source_enabled( $item ? $item->{source} : undef,
        $data->{hostname} );
}

=head2 C<< $class->status( $import_data, $item, $args ) >>

This creates an LJ::Event::ImportStatus item for the user to look at.  Note that $args
is a hashref that is passed straight through in the item.

=cut

sub status {
    my ( $class, $imp, $item, $args ) = @_;
    foreach my $uid ( $class->userids_to_message( $imp->{userid} ) ) {
        LJ::Event::ImportStatus->new( $uid, $item, { type => 'status', %{ $args || {} } } )->fire;
    }
}

=head1 AUTHORS

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
