#!/usr/bin/perl
#
# DW::Logic::Importer
#
# This module provides logic for various importer front-end functions.
#
# Authors:
#      Janine Costanzo <janine@netrophic.com>
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

sub get_import_data_for_user {
    my ( $class, $u ) = @_;

    my $dbh = LJ::get_db_writer()
        or die "No database.";

    # load up their most recent (active) import
    # FIXME: memcache this
    my $imports = $dbh->selectall_arrayref(
        'SELECT import_data_id, hostname, username, password_md5 FROM import_data WHERE userid = ? ' .
        'ORDER BY import_data_id DESC LIMIT 1',
        undef, $u->id
    );

    return $imports;
}

sub get_import_items_for_user {
    my ( $class, $u ) = @_;

    my $imports = DW::Logic::Importer->get_import_data_for_user( $u );
    my %items;
    my $dbh = LJ::get_db_writer()
        or die "No database.";

    my $has_items = 0;
    foreach my $import ( @$imports ) {
        my ( $importid, $host, $username, $password ) = @$import;
        $items{$importid} = { host => $host, user => $username, pw => $password, items => {} };

        my $import_items = $dbh->selectall_arrayref(
            'SELECT item, status, created, last_touch FROM import_items WHERE userid = ? AND import_data_id = ?',
            undef, $u->id, $importid
        );

        foreach my $import_item ( @$import_items ) {
            $items{$importid}->{items}->{$import_item->[0]} = {
                status => $import_item->[1], created => $import_item->[2], last_touch => $import_item->[3]
            };
            $has_items = 1 if $import_item->[0];
        }
    }

    return $has_items ? \%items : {};
}

sub set_import_data_for_user {
    my ( $class, $u, %opts ) = @_;

    my $hn = $opts{hostname};
    my $un = $opts{username};
    my $pw = $opts{password};

    return "Did not pass hostname, username, and password."
        unless $hn && $un && $pw;

    my $dbh = LJ::get_db_writer()
        or return "Unable to connect to database.";

    my $id = LJ::alloc_user_counter( $u, "I" ) or return "Can't get id for import data.";
    $dbh->do(
        "INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) VALUES (?, ?, ?, ?, ?)",
        undef, $u->id, $id, $hn, $un, md5_hex( $pw )
    );
    return $dbh->errstr if $dbh->err;

    # this is a hack, but we use it until we get a better frontend.  we abort all
    # existing import jobs if they schedule a new one.  this won't actually stop any
    # TheSchwartz jobs thateare in progress, of course, but that should be okay
    $dbh->do(
        q{UPDATE import_items SET status = 'aborted'
          WHERE userid = ? AND status IN ('init', 'ready', 'queued')},
        undef, $u->id
    );

    return "";
}

sub set_import_items_for_user {
    my ( $class, $u, %opts ) = @_;

    my $item = $opts{item};
    my $id = $opts{id}+0;

    return "Did not pass item and id."
        unless ref $item eq 'ARRAY' && $id > 0;

    my $dbh = LJ::get_db_writer()
        or return "Unable to connect to database.";

    # paid accounts get higher priority than free ones
    my $account_type = DW::Pay::get_account_type( $u );
    my $priority = 100;
    if ( $account_type eq "seed" || $account_type eq "premium" ) {
        $priority = 400;
    } elsif ( $account_type eq 'paid' ) {
        $priority = 300;
    }

    $dbh->do(
        "INSERT INTO import_items (userid, item, status, created, import_data_id, priority) " .
        "VALUES (?, ?, ?, UNIX_TIMESTAMP(), ?, ?)",
        undef, $u->id, $item->[0], $item->[1], $id, $priority
    );
    return $dbh->errstr if $dbh->err;

    return "";
}

1;
