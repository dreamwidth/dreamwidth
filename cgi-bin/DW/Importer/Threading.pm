#!/usr/bin/perl
#
# DW::Importer::Threading
#
# Orders imported comments so replies follow what they reply to.
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

package DW::Importer::Threading;

=head1 NAME

DW::Importer::Threading - Parent-first ordering of imported comments

=head1 SYNOPSIS

    my $threads = DW::Importer::Threading->new(
        entries => { $remote_entry_id => $local_entry_id },
        known   => { $remote_comment_id => $local_comment_id },
    );

    foreach my $comment (@window) {
        my ( $what, $local_id ) = $threads->add($comment);
        # 'existing': we already have it, as $local_id
        # 'unmapped_entry': its entry isn't imported, it will never be written
        # 'pending': waiting to be written
    }

    $threads->process( sub {
        my ( $comment, $local_parent_id, $local_entry_id ) = @_;
        return write_it( ... );     # the new local id
    } );

    my @orphans = $threads->orphans;   # at the very end

=head1 DESCRIPTION

A comment can only be written once the comment it replies to has a local id. Comments
arrive in windows in id order, but a reply isn't always after its parent, and a parent
can arrive in a later window than its reply. C<add> collects them, C<process> writes
everything that can be written, parents first, keeping the rest for the next call,
and C<orphans> reports what never found a parent.

Records are the comment records of L<DW::Importer::Records>.

=cut

use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;
    return bless {
        entries  => $args{entries} || {},
        known    => { %{ $args{known} || {} } },
        pending  => {},
        unmapped => [],
        written  => 0,
    }, $class;
}

=head2 C<< $threads->add( $comment ) >>

Returns C<( 'existing', $local_id )> if the comment has already been imported,
C<('unmapped_entry')> if the entry it belongs to is not known, or C<('pending')> if it
was queued to be written.

=cut

sub add {
    my ( $self, $comment ) = @_;

    my $known = $self->{known}->{ $comment->{remote_id} };
    return ( 'existing', $known ) if $known;

    unless ( $self->{entries}->{ $comment->{entry_id} } ) {
        push @{ $self->{unmapped} }, $comment;
        return ('unmapped_entry');
    }

    $self->{pending}->{ $comment->{remote_id} } = $comment;
    return ('pending');
}

=head2 C<< $threads->local_id( $remote_comment_id ) >>

The local id of a comment that is already imported, or was written by C<process>.

=cut

sub local_id { return $_[0]->{known}->{ $_[1] } }

=head2 C<< $threads->process( $writer ) >>

Calls C<$writer> for each queued comment whose parent is a top level comment or has a
local id already, in ascending order of remote id, repeating until nothing more can be
written. C<$writer> gets the comment, the local id of the parent (0 for top level) and
the local id of the entry, and returns the new local id of the comment. A false return
leaves the comment queued. Returns how many were written.

=cut

sub process {
    my ( $self, $writer ) = @_;

    my $written = 0;
    my $progress;
    do {
        $progress = 0;
        foreach my $id ( sort { $a <=> $b } keys %{ $self->{pending} } ) {
            my $comment = $self->{pending}->{$id};
            my $parent  = $comment->{parent_id};

            my $local_parent = 0;
            if ($parent) {
                $local_parent = $self->{known}->{$parent};
                next unless defined $local_parent;
            }

            my $local =
                $writer->( $comment, $local_parent, $self->{entries}->{ $comment->{entry_id} } )
                or next;

            $self->{known}->{$id} = $local;
            delete $self->{pending}->{$id};
            $written++;
            $progress = 1;
        }
    } while ($progress);

    return $written;
}

=head2 C<< $threads->orphans >>

The comments still queued: replies whose parent was never imported, in id order.

=cut

sub orphans {
    my ($self) = @_;
    return map { $self->{pending}->{$_} } sort { $a <=> $b } keys %{ $self->{pending} };
}

=head2 C<< $threads->unmapped >>

The comments that were skipped because their entry isn't imported, in the order added.

=cut

sub unmapped { return @{ $_[0]->{unmapped} } }

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
