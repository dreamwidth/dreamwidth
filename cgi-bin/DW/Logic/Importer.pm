#!/usr/bin/perl
#
# DW::Logic::Importer
#
# This module provides logic for various importer front-end functions.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::Importer;

use strict;
use Digest::MD5 qw/ md5_hex /;
use DW::Pay;
use Storable;

=head1 API

=head2 C<<DW::Logic::Importer->get_import_data( $u, id1, [ id2, id3 ] )>>

Get import data for this user for all provided import ids

=cut

sub get_import_data {
    my ( $class, $u, @ids ) = @_;

    return [] unless @ids;

    my $dbh = LJ::get_db_writer()
        or die "No database.";

    my $qs = join ",", map { "?" } @ids;

    # FIXME: memcache this
    my $imports = $dbh->selectall_arrayref(
"SELECT import_data_id, hostname, username, usejournal, password_md5, options FROM import_data WHERE userid = ? AND import_data_id IN ( $qs ) "
            . "ORDER BY import_data_id ASC",
        undef, $u->id, @ids
    );

    foreach my $import ( @{ $imports || [] } ) {
        $import->[5] = Storable::thaw( $import->[5] ) || {}
            if $import->[5];
    }

    return $imports;
}

=head2 C<<DW::Logic::Importer->get_import_data_for_user>>

Get the latest import data for this user

=cut

sub get_import_data_for_user {
    my ( $class, $u ) = @_;

    my $dbh = LJ::get_db_writer()
        or die "No database.";

    # load up their most recent (active) import
    # FIXME: memcache this
    my $imports = $dbh->selectall_arrayref(
'SELECT import_data_id, hostname, username, usejournal, password_md5, options FROM import_data WHERE userid = ? '
            . 'ORDER BY import_data_id DESC LIMIT 1',
        undef, $u->id
    );

    $imports->[0]->[5] = Storable::thaw( $imports->[0]->[5] ) || {}
        if $imports && $imports->[0] && $imports->[0]->[5];

    return $imports;
}

=head2 C<<DW::Logic::Importer->get_import_items( $u, id1, [ id2, id3... ] )>>

Get import items for this user for all provided import ids.

=cut

sub get_import_items {
    my ( $class, $u, @importids ) = @_;

    my $dbh = LJ::get_db_writer()
        or die "No database.";

    my $qs = join ",", map { "?" } @importids;

    my $import_items = $dbh->selectall_arrayref(
"SELECT import_data_id, item, status, created, last_touch FROM import_items WHERE userid = ? AND import_data_id IN ( $qs )",
        undef, $u->id, @importids
    );

    my %ret;
    foreach my $import_item (@$import_items) {
        my ( $id, $item, $status, $created, $last_touch ) = @$import_item;
        $ret{$id}->{$item} = {
            status     => $status,
            created    => $created,
            last_touch => $last_touch,
        };
    }

    return \%ret;
}

=head2 C<<DW::Logic::Importer->get_all_import_items( $u )>>

Get all import items for this user

=cut

sub get_all_import_items {
    my ( $class, $u ) = @_;

    my $dbh = LJ::get_db_writer()
        or die "No database.";

    my $import_items = $dbh->selectall_arrayref(
"SELECT import_data_id, item, status, created, last_touch FROM import_items WHERE userid = ?",
        undef, $u->id
    );

    my %ret;
    foreach my $import_item (@$import_items) {
        my ( $id, $item, $status, $created, $last_touch ) = @$import_item;
        $ret{$id}->{$item} = {
            status     => $status,
            created    => $created,
            last_touch => $last_touch,
        };
    }

    return \%ret;
}

=head2 C<<DW::Logic::Importer->get_import_items_for_user( $u, id1, [ id2, id3... ] )>>

Get latest import item for this user. Includes import data.

=cut

sub get_import_items_for_user {
    my ( $class, $u ) = @_;

    my $imports = DW::Logic::Importer->get_import_data_for_user($u);
    my %items;

    my $has_items = 0;
    foreach my $import (@$imports) {
        my ( $importid, $host, $username, $usejournal, $password ) = @$import;
        $items{$importid} = {
            host       => $host,
            user       => $username,
            pw         => $password,
            usejournal => $usejournal,
            items      => DW::Logic::Importer->get_import_items( $u, $importid )->{$importid},
        };

        $has_items = 1 if scalar keys %{ $items{$importid}->{items} };
    }

    return $has_items ? \%items : {};
}

=head2 C<<DW::Logic::Importer->get_queued_imports( $u )>>

Get a list of imports that have yet to be processed. May be in the schwartz
queue, and thus running soon; or else in the import queue, and have yet to be
put into the schwartz queue. The latter may not run if they are duplicates of
something in the schwartz queue.

=cut

sub get_queued_imports {
    my ( $class, $u ) = @_;

    return {} unless $u;

    # the latest import the user has queued
    my $latestimport = DW::Logic::Importer->get_import_data_for_user($u);

    # the latest job that's currently running
    # should be <= $latestimport
    my $runningjob = $u->prop("import_job");

    return {} unless $latestimport && $runningjob;

    return DW::Logic::Importer->get_import_items( $u, $runningjob .. $latestimport->[0]->[0] );
}

sub set_import_data_for_user {
    my ( $class, $u, %opts ) = @_;

    my $hn = $opts{hostname};
    my $un = $opts{username};
    my $pw = $opts{password};
    my $uj = $opts{usejournal};

    return "Did not pass hostname, username, and password."
        unless $hn && $un && $pw;

    my $dbh = LJ::get_db_writer()
        or return "Unable to connect to database.";

    my $id = LJ::alloc_user_counter( $u, "I" ) or return "Can't get id for import data.";
    $dbh->do(
"INSERT INTO import_data (userid, import_data_id, hostname, username, usejournal, password_md5) VALUES (?, ?, ?, ?, ?, ?)",
        undef, $u->id, $id, $hn, $un, $uj, md5_hex($pw)
    );
    return $dbh->errstr if $dbh->err;

    # this is a hack, but we use it until we get a better frontend.  we abort all
    # existing import jobs if they schedule a new one.  this won't actually stop any
    # TheSchwartz jobs that are in progress, of course, but that should be okay
    $dbh->do(
        q{UPDATE import_items SET status = 'aborted'
          WHERE userid = ? AND status IN ('init', 'ready', 'queued')},
        undef, $u->id
    );

    return undef;
}

sub set_import_data_options_for_user {
    my ( $class, $u, %opts ) = @_;

    my $id = delete $opts{import_data_id};
    return unless %opts;

    my $data = Storable::nfreeze( \%opts );

    my $dbh = LJ::get_db_writer()
        or return "Unable to connect to database.";

    $dbh->do( "UPDATE import_data SET options = ? WHERE import_data_id = ?", undef, $data, $id );

    return $dbh->errstr if $dbh->err;

    return undef;
}

sub set_import_items_for_user {
    my ( $class, $u, %opts ) = @_;

    my $item = $opts{item};
    my $id   = $opts{id} + 0;

    return "Did not pass item and id."
        unless ref $item eq 'ARRAY' && $id > 0;

    my $dbh = LJ::get_db_writer()
        or return "Unable to connect to database.";

    # paid accounts get higher priority than free ones
    my $account_type = DW::Pay::get_account_type($u);
    my $priority     = 100;
    if ( $account_type eq "seed" || $account_type eq "premium" ) {
        $priority = 400;
    }
    elsif ( $account_type eq 'paid' ) {
        $priority = 300;
    }

    $dbh->do(
        "INSERT INTO import_items (userid, item, status, created, import_data_id, priority) "
            . "VALUES (?, ?, ?, UNIX_TIMESTAMP(), ?, ?)",
        undef, $u->id, $item->[0], $item->[1], $id, $priority
    );
    return $dbh->errstr if $dbh->err;

    return "";
}

1;
