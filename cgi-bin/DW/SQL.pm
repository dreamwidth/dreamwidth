#!/usr/bin/perl
#
# DW::SQL
#
# Structured SQL construction over SQL::Abstract. Values never appear in the
# SQL string -- every one becomes a bind parameter -- so call sites can't
# accidentally interpolate user data into a query.
#
# This is deliberately NOT an ORM: it returns plain rows and works with the
# handles the caller already has ($u, a cluster reader, the global master), so
# it layers onto the existing routing instead of replacing it.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::SQL;

use strict;
use warnings;
use v5.10;

use Carp qw( croak );
use SQL::Abstract;

# One shared generator; SQL::Abstract keeps no per-query state.
my $sqla = SQL::Abstract->new;

# All functions take a database handle first: anything with the DBI do/prepare
# interface, which includes $u (LJ::User delegates), cluster readers, and the
# global master/slave handles.

# rows( $db, $table, \@cols, \%where, \%opts ) -> arrayref of hashrefs
#
# Columns are trusted strings (they may be expressions like "COUNT(*)" or
# "UNIX_TIMESTAMP(picdate) AS picdate"); everything in \%where becomes a bind
# parameter. \%opts supports order_by (SQL::Abstract order spec) and limit
# (positive integer).
sub rows {
    my ( $db, $table, $cols, $where, $opts ) = @_;
    croak "no database handle" unless $db;
    $opts //= {};

    my ( $sql, @bind ) = $sqla->select( $table, $cols, $where, $opts->{order_by} );
    $sql .= _limit_clause( $opts->{limit} ) if defined $opts->{limit};

    my $sth = $db->prepare($sql);
    $sth->execute(@bind);
    croak $db->errstr if $db->err;
    return $sth->fetchall_arrayref( {} );
}

# row( ... ) -> first row as hashref, or undef. Same arguments as rows();
# forces limit 1.
sub row {
    my ( $db, $table, $cols, $where, $opts ) = @_;
    my $rows = rows( $db, $table, $cols, $where, { %{ $opts // {} }, limit => 1 } );
    return $rows->[0];
}

# insert( $db, $table, \%values )
sub insert {
    my ( $db, $table, $values ) = @_;
    return _do( $db, $sqla->insert( $table, $values ) );
}

# replace( $db, $table, \%values ) -- MySQL REPLACE INTO.
sub replace {
    my ( $db, $table, $values ) = @_;
    my ( $sql, @bind ) = $sqla->insert( $table, $values );
    $sql =~ s/\AINSERT INTO/REPLACE INTO/;
    return _do( $db, $sql, @bind );
}

# insert_ignore( $db, $table, \%values ) -- MySQL INSERT IGNORE.
sub insert_ignore {
    my ( $db, $table, $values ) = @_;
    my ( $sql, @bind ) = $sqla->insert( $table, $values );
    $sql =~ s/\AINSERT INTO/INSERT IGNORE INTO/;
    return _do( $db, $sql, @bind );
}

# update( $db, $table, \%set, \%where )
#
# Set expressions like "count = count + 1" are written as scalar refs:
#   { count => \"count + 1" }
sub update {
    my ( $db, $table, $set, $where ) = @_;
    return _do( $db, $sqla->update( $table, $set, $where ) );
}

# delete_from( $db, $table, \%where ) -- named to avoid CORE::delete confusion.
# An empty/missing where clause is refused; a full-table delete must be
# hand-written SQL so it's visible in review.
sub delete_from {
    my ( $db, $table, $where ) = @_;
    croak "refusing unconditional delete from $table"
        unless ref $where && %$where;
    return _do( $db, $sqla->delete( $table, $where ) );
}

sub _do {
    my ( $db, $sql, @bind ) = @_;
    my $rv = $db->do( $sql, undef, @bind );
    croak $db->errstr if $db->err;
    return $rv;
}

# LIMIT can't be a bind parameter everywhere, so it's validated and inlined.
sub _limit_clause {
    my $limit = shift;
    croak "limit must be a positive integer" unless $limit =~ /\A[0-9]+\z/;
    return " LIMIT $limit";
}

1;
