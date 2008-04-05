#!/usr/bin/perl
package LJ::WorkerResultStorage;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $handle = delete $opts{handle} or croak "No handle";

    my $self = {
        handle => $handle,
    };

    return bless $self, $class;
}

sub handle { $_[0]->{handle} }

sub save_status {
    my ($self, %row) = @_;

    my $handle = $self->handle;

    my (@cols, @values);
    foreach my $col (qw(result status)) {
        my $val = $row{$col};
        next unless $val;

        push @cols, $col;
        push @values, $val;
    }

    my $setbind = join ',', map { "$_=?" } @cols;

    # end_time needs to be special-cased to use UNIX_TIMESTAMP()
    $setbind .= ($setbind ? ',' : '') . 'end_time=UNIX_TIMESTAMP()' if $row{end_time};

    my $dbh = LJ::get_db_writer() or die "Could not get DB writer";
    $dbh->do("UPDATE jobstatus SET $setbind WHERE handle=?",
             undef, @values, $handle);
    die $dbh->errstr if $dbh->err;

    # lazy cleaning
    if (rand(100) < 20) {
        # clean results older than one day
        $dbh->do("DELETE FROM jobstatus WHERE start_time > 0 AND UNIX_TIMESTAMP() - 86400 > start_time");
        die $dbh->errstr if $dbh->err;
    }

    return 1;
}

# save this job's status (even though it has none) so that we have a record
# in the database that the job has started
sub init_job {
    my ($self) = @_;

    my $dbh = LJ::get_db_writer() or die "Could not get DB writer";
    $dbh->do("INSERT INTO jobstatus (handle, status, start_time) VALUES " .
             "(?, ?, UNIX_TIMESTAMP())", undef, $self->handle, 'running');
    die $dbh->errstr if $dbh->err;

    return 1;
}

# get info about a job
# returns a hash containing job status or undef if no job info available
sub status {
    my $self = shift;

    # get current job status from gearman if it's still running
    my $gc = LJ::gearman_client() or die "Could not get german client";
    my $gm_status = $gc->get_status($self->handle);

    my (%gearman_status, %rowinfo);

    if ($gm_status) {
        my $progress = $gm_status->progress || [0, 0];
        my $percent  = $gm_status->percent || 0;
        %gearman_status = (progress => $progress, percent => $percent);
        $gearman_status{status} = 'running' if $gm_status->running;
    }

    if (! $gm_status || ! $gm_status->running) {
        # got no info from gearman or task is not running, query db to see if we have info on this job
        my $dbh = LJ::get_db_writer() or die "Could not get DB handle";
        my $row = $dbh->selectrow_hashref("SELECT handle, result, status, start_time, end_time " .
                                          "FROM jobstatus WHERE handle=?", undef, $self->handle);
        die $dbh->errstr if $dbh->err;

        if ($row) {
            for (qw(status start_time end_time result)) {
                $rowinfo{$_} = $row->{$_} if defined $row->{$_};
            }
        }
    }

    # no info from gearman or database.
    return undef unless %rowinfo || $gm_status;

    my %status = (%rowinfo, %gearman_status);

    return %status;
}

1;
