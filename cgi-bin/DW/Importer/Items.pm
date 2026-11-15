#!/usr/bin/perl
#
# DW::Importer::Items
#
# Moves the items of an import through their lifecycle as jobs finish.
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

package DW::Importer::Items;

=head1 NAME

DW::Importer::Items - Dependency chaining for the items of an import

=head1 DESCRIPTION

An import is a set of rows in C<import_items>, one per item, each in a status of
C<init> (waiting), C<ready> (the scheduler may queue it), C<queued>, C<succeeded>,
C<failed> or C<aborted>. Which item waits for which is declared in
L<DW::Importer::Registry>; this module applies it when a job finishes.

=cut

use strict;
use warnings;

use DW::Importer::Registry;

=head2 C<< DW::Importer::Items->advance( $u, $import_data_id, $item, $outcome ) >>

Call after C<$item> has finished for the import. C<$outcome> is C<success> or
C<failure> (a permanent failure).

On success, every waiting (C<init>) item that depends on C<$item> and whose
dependencies have now all succeeded becomes C<ready>. On failure, every waiting
item that depends on it, directly or through other waiting items, becomes
C<aborted>, since it can never run.

Returns a hashref with the C<ready> or C<aborted> item names.

=cut

sub advance {
    my ( $class, $u, $import_data_id, $item, $outcome ) = @_;

    my %result = ( ready => [], aborted => [] );
    return \%result unless DW::Importer::Registry->item($item);

    my $dbh = LJ::get_db_writer()
        or return \%result;

    my $rows = $dbh->selectall_arrayref(
        'SELECT item, status FROM import_items ' . 'WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $import_data_id );
    return \%result unless $rows;

    my %status      = map { $_->[0] => $_->[1] } @$rows;
    my $journaltype = DW::Importer::Registry->journaltype($u);

    if ( $outcome eq 'success' ) {
        $status{$item} = 'succeeded';

        foreach my $dep ( DW::Importer::Registry->dependents( $item, $journaltype ) ) {
            next unless ( $status{$dep} // '' ) eq 'init';
            next if _blocked( \%status, $journaltype, $dep );

            push @{ $result{ready} }, $dep;
        }
        $class->_set_status( $dbh, $u, $import_data_id, 'ready', $result{ready} );
    }
    elsif ( $outcome eq 'failure' ) {
        my %doomed = ( $item => 1 );
        my @queue  = ($item);
        while ( defined( my $failed = shift @queue ) ) {
            foreach my $dep ( DW::Importer::Registry->dependents( $failed, $journaltype ) ) {
                next unless ( $status{$dep} // '' ) eq 'init';
                next if $doomed{$dep}++;

                push @{ $result{aborted} }, $dep;
                push @queue, $dep;
            }
        }
        $class->_set_status( $dbh, $u, $import_data_id, 'aborted', $result{aborted} );
    }
    else {
        die "unknown outcome '$outcome'\n";
    }

    return \%result;
}

# true if one of the item's dependencies is part of this import and has not succeeded; a
# dependency that isn't part of the import doesn't hold anything up
sub _blocked {
    my ( $status, $journaltype, $item ) = @_;
    return
        scalar grep { exists $status->{$_} && $status->{$_} ne 'succeeded' }
        DW::Importer::Registry->depends_on( $item, $journaltype );
}

=head2 C<< DW::Importer::Items->release( $u, $import_data_id, \@items ) >>

For items that have just been put back to C<init> (see L<DW::Importer::Control>): each
one whose dependencies in this import have all succeeded becomes C<ready>, so the
scheduler picks it up; the others keep waiting for whatever they depend on. Only items
that are still C<init> are touched.

Returns a hashref with the C<ready> items and the C<waiting> ones.

=cut

sub release {
    my ( $class, $u, $import_data_id, $items ) = @_;

    my %result = ( ready => [], waiting => [] );
    my $dbh    = LJ::get_db_writer()
        or return \%result;

    my $rows = $dbh->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $import_data_id );
    return \%result unless $rows;

    my %status      = map { $_->[0] => $_->[1] } @$rows;
    my $journaltype = DW::Importer::Registry->journaltype($u);

    foreach my $item (@$items) {
        next unless ( $status{$item} // '' ) eq 'init' && DW::Importer::Registry->item($item);
        push @{ $result{ _blocked( \%status, $journaltype, $item ) ? 'waiting' : 'ready' } }, $item;
    }
    $class->_set_status( $dbh, $u, $import_data_id, 'ready', $result{ready} );

    return \%result;
}

# only items still waiting are touched, so two jobs finishing together can't undo each other
sub _set_status {
    my ( $class, $dbh, $u, $import_data_id, $status, $items ) = @_;
    return unless @$items;

    my $placeholders = join ',', map { '?' } @$items;
    $dbh->do(
        "UPDATE import_items SET status = ? "
            . "WHERE userid = ? AND import_data_id = ? AND status = 'init' "
            . "AND item IN ($placeholders)",
        undef, $status, $u->id, $import_data_id, @$items
    );
    warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
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
