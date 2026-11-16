#!/usr/bin/perl
#
# DW::Test::Importer
#
# Helpers for the importer's tests.
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

package DW::Test::Importer;

=head1 NAME

DW::Test::Importer - Shared helpers for the importer tests

=cut

use strict;
use warnings;

use Digest::MD5 qw( md5_hex );

use base 'Exporter';
our @EXPORT_OK = qw( snapshot );

# cluster tables and the column that says which user the row belongs to
my %CLUSTER_TABLES = (
    log2          => 'journalid',
    logtext2      => 'journalid',
    logprop2      => 'journalid',
    logtags       => 'journalid',
    logsec2       => 'journalid',
    talk2         => 'journalid',
    talktext2     => 'journalid',
    talkprop2     => 'journalid',
    talkleft      => 'userid',
    userpic2      => 'userid',
    userpicmap3   => 'userid',
    usertags      => 'journalid',
    trust_groups  => 'userid',
    reluser2      => 'userid',
    userbio       => 'userid',
    userkeywords  => 'userid',
    import_status => 'userid',
    userproplite2 => 'userid',
    userpicblob2  => 'userid',
    memkeyword2   => 'userid',
);

# tables that are not per user, so the whole table is counted
my @GLOBAL_TABLES =
    qw( user import_usermap identitymap import_items import_status userinterests userpic2 userprop userproplite );

=head2 C<< snapshot( $u ) >>

Everything an import could change about C<$u>: how many rows each of the tables it
writes has for that user (and, for tables that aren't per user, in total), plus a digest
of the user's import rows. Two snapshots are equal if nothing was written between.

=cut

sub snapshot {
    my ($u) = @_;

    my %snap;
    foreach my $table ( sort keys %CLUSTER_TABLES ) {
        my $col = $CLUSTER_TABLES{$table};
        my ($count) =
            $u->selectrow_array( "SELECT COUNT(*) FROM $table WHERE $col = ?", undef, $u->id );
        $snap{"cluster:$table"} = $count // 0;
    }

    my $dbh = LJ::get_db_writer();
    foreach my $table (@GLOBAL_TABLES) {
        my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM $table");
        $snap{"global:$table"} = $count // 0;
    }

    my $rows = $dbh->selectall_arrayref(
        'SELECT import_data_id, hostname, username, usejournal, groupmap, options FROM import_data '
            . 'WHERE userid = ? ORDER BY import_data_id',
        undef, $u->id
    );
    $snap{import_data} = md5_hex(
        join "\0",
        map {
            map { $_ // '' }
                @$_
        } @$rows
    );

    $rows = $dbh->selectall_arrayref(
        'SELECT import_data_id, item, status, last_touch FROM import_items WHERE userid = ? '
            . 'ORDER BY import_data_id, item',
        undef, $u->id
    );
    $snap{import_items_state} = md5_hex(
        join "\0",
        map {
            map { $_ // '' }
                @$_
        } @$rows
    );

    return \%snap;
}

1;
