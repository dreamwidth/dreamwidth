#!/usr/bin/perl
#
# DW::Worker::ContentImporter
#
# Generic helper functions for Content Importers
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter;

=head1 NAME

DW::Worker::ContentImporter - Generic helper functions for Content Importers

=cut

use strict;
use Time::HiRes qw/ sleep time /;
use Carp qw/ croak confess /;
use Storable;
use LWP::UserAgent;
use XMLRPC::Lite;
use Digest::MD5 qw/ md5_hex /;

use LJ::Protocol;
use LJ::Talk;

use base 'TheSchwartz::Worker';

=head1 Saving API

All Saving API functions take as the first two options the target user
option, followed by a consistent hashref passed to every function.

=head2 C<< $class->merge_trust( $user, $hashref, $friends ) >>

$friends is a reference to an array of hashrefs, with each hashref with the following format:

  {
      userid => ...,        # local userid of the friend
      groupmask => 1,       # groupmask
  }

=cut

sub merge_trust {
    my ( $class, $u, $opts, $friends ) = @_;
    foreach my $friend (@$friends) {
        my $to_u = LJ::load_userid( $friend->{userid} );
        $u->add_edge( $to_u, trust => { mask => $friend->{groupmask}, nonotify => 1, } );
    }
}

=head2 C<< $class->merge_watch( $user, $hashref, $friends ) >>

$friends is a reference to an array of hashrefs, with each hashref with the following format:

  {
      userid => ...,        # local userid of the friend
      fgcolor => '#ff0000', # foreground color
      bgcolor => '#00ff00', # background color
  }

=cut

sub merge_watch {
    my ( $class, $u, $opts, $friends ) = @_;
    foreach my $friend (@$friends) {
        my $to_u = LJ::load_userid( $friend->{userid} );
        $u->add_edge(
            $to_u,
            watch => {
                nonotify => 1,
                fgcolor  => LJ::color_todb( $friend->{fgcolor} ),
                bgcolor  => LJ::color_todb( $friend->{bgcolor} ),
            }
        );
    }
}

=head1 Helper Functions

=head2 C<< $class->import_data( $userid, $import_data_id ) >>

Returns a hash of the data we're using as source.

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

=head2 C<< $class->fail( $import_data, $item, $job, "text", [arguments, ...] ) >>

Permanently fail this import job.

=cut

sub fail {
    my ( $class, $imp, $item, $job, $msgt, @args ) = @_;
    $0 = 'content-importer [bored]';

    if ( my $dbh = LJ::get_db_writer() ) {
        $dbh->do(
            "UPDATE import_items SET status = 'failed', last_touch = UNIX_TIMESTAMP() "
                . "WHERE userid = ? AND item = ? AND import_data_id = ?",
            undef, $imp->{userid}, $item, $imp->{import_data_id}
        );
        warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
    }

    my $msg = sprintf( $msgt, @args );
    warn "Permanent failure: $msg\n"
        if $LJ::IS_DEV_SERVER;

    # fire an event for the user to know that it failed
    foreach my $uid ( $class->userids_to_message( $imp->{userid} ) ) {
        LJ::Event::ImportStatus->new( $uid, $item, { type => 'fail', msg => $msg } )->fire;
    }

    $job->permanent_failure($msg);
    return;
}

=head2 C<< $class->temp_fail( $job, "text", [arguments, ...] ) >>

Temporarily fail this import job, it will get retried if it hasn't failed too many times.

=cut

sub temp_fail {
    my ( $class, $imp, $item, $job, $msgt, @args ) = @_;
    $0 = 'content-importer [bored]';

    # Check if we are out of failures
    my $max_fails = $class->max_retries;
    my $this_fail = $job->failures + 1;    # Add this failure on.
    return $class->fail( $imp, $item, $job, $msgt, @args ) if $this_fail >= $max_fails;

    my $msg = sprintf( $msgt, @args );
    warn "Temporary failure: $msg\n"
        if $LJ::IS_DEV_SERVER;

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
    return;
}

=head2 C<< $class->ok( $import_data, $item, $job, $show ) >>

Successfully end this import job.

=cut

sub ok {
    my ( $class, $imp, $item, $job, $show ) = @_;
    $0 = 'content-importer [bored]';

    if ( my $dbh = LJ::get_db_writer() ) {
        $dbh->do(
            "UPDATE import_items SET status = 'succeeded', last_touch = UNIX_TIMESTAMP() "
                . "WHERE userid = ? AND item = ? AND import_data_id = ?",
            undef, $imp->{userid}, $item, $imp->{import_data_id}
        );
        warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
    }

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
    return LJ::is_enabled( "importing", $data->{hostname} );
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

1;
