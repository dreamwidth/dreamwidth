#!/usr/bin/perl
#
# DW::Importer::Report
#
# What a dry run found it would do.
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

package DW::Importer::Report;

=head1 NAME

DW::Importer::Report - The result of an import run that wrote nothing

=head1 DESCRIPTION

A dry run (see L<DW::Importer::Sink::DryRun>) puts what it would have written into a
report: the actions, with counts per type, the items it would have skipped because they
were already imported, the warnings the user would have been given and the content it
could not place.

=cut

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {
        actions  => [],
        skips    => [],
        warnings => [],
        orphans  => [],
        unmapped => [],
        statuses => [],
        outcomes => [],
    }, $class;
}

=head2 Recording

=over

=item C<< $report->add_action( type => 'entry', target => $key, summary => '...', record => $r ) >>

A write that would have been made. See L<DW::Importer::Records>.

=item C<< $report->add_skip( type => 'entry', target => $key, reason => '...', [ count => N ] ) >>

Something that was left alone because it is already there. C<count> stands for several.

=item C<< $report->add_warning( $text, [ target => $key ] ) >>

Something the user would have been told about.

=item C<< $report->add_orphan( %details ) >>, C<< $report->add_unmapped( %details ) >>

A comment whose parent was not imported, or whose entry was not.

=item C<< $report->add_status( %args ) >>

A status notification the user would have been sent.

=item C<< $report->add_outcome( $item, $outcome ) >>

How a job ended: an L<DW::Importer::Outcome>.

=back

=cut

sub add_action   { my ( $self, %a ) = @_; push @{ $self->{actions} },  {%a}; return }
sub add_skip     { my ( $self, %a ) = @_; push @{ $self->{skips} },    {%a}; return }
sub add_orphan   { my ( $self, %a ) = @_; push @{ $self->{orphans} },  {%a}; return }
sub add_unmapped { my ( $self, %a ) = @_; push @{ $self->{unmapped} }, {%a}; return }
sub add_status   { my ( $self, %a ) = @_; push @{ $self->{statuses} }, {%a}; return }

sub add_warning {
    my ( $self, $text, %a ) = @_;
    push @{ $self->{warnings} }, { text => $text, %a };
    return;
}

sub add_outcome {
    my ( $self, $item, $outcome ) = @_;
    push @{ $self->{outcomes} }, { item => $item, outcome => $outcome };
    return;
}

=head2 Reading

C<actions>, C<skips>, C<warnings>, C<orphans>, C<unmapped>, C<statuses> and C<outcomes>
return the lists, in the order things happened. C<actions_of( $type )> returns the
actions of one type.

=cut

sub actions  { @{ $_[0]->{actions} } }
sub skips    { @{ $_[0]->{skips} } }
sub warnings { @{ $_[0]->{warnings} } }
sub orphans  { @{ $_[0]->{orphans} } }
sub unmapped { @{ $_[0]->{unmapped} } }
sub statuses { @{ $_[0]->{statuses} } }
sub outcomes { @{ $_[0]->{outcomes} } }

sub actions_of {
    my ( $self, $type ) = @_;
    return grep { $_->{type} eq $type } @{ $self->{actions} };
}

=head2 C<< $report->counts >>

A hashref of action type to how many there were.

=cut

sub counts {
    my ($self) = @_;
    my %counts;
    $counts{ $_->{type} }++ foreach @{ $self->{actions} };
    return \%counts;
}

=head2 C<< $report->as_text >>

The report for a person to read.

=cut

sub as_text {
    my ($self) = @_;

    my @lines;
    my $counts = $self->counts;
    push @lines, 'Would write:';
    push @lines, map { sprintf( '  %-16s %d', $_, $counts->{$_} ) } sort keys %$counts;
    push @lines, '  nothing' unless %$counts;

    foreach my $action ( @{ $self->{actions} } ) {
        push @lines,
            sprintf( '    [%s] %s', $action->{type},
            $action->{summary} // $action->{target} // '' );
    }

    my $skipped = 0;
    $skipped += $_->{count} // 1 foreach @{ $self->{skips} };
    if ($skipped) {
        push @lines, '', "Would skip $skipped already imported:";
        foreach my $skip ( @{ $self->{skips} } ) {
            push @lines,
                sprintf( '    [%s] %s: %s',
                $skip->{type}, $skip->{target} // "$skip->{count} items",
                $skip->{reason} );
        }
    }

    if ( @{ $self->{unmapped} } ) {
        push @lines, '', 'Comments on entries that are not imported:';
        push @lines,
            map { sprintf( '    comment %s (entry %s)', $_->{remote_id}, $_->{entry_id} ) }
            @{ $self->{unmapped} };
    }
    if ( @{ $self->{orphans} } ) {
        push @lines, '', 'Comments whose parent is not imported:';
        push @lines,
            map { sprintf( '    comment %s (reply to %s)', $_->{remote_id}, $_->{parent_id} ) }
            @{ $self->{orphans} };
    }
    if ( @{ $self->{warnings} } ) {
        push @lines, '', 'Warnings:';
        push @lines,
            map { '    ' . ( defined $_->{target} ? "$_->{target}: " : '' ) . $_->{text} }
            @{ $self->{warnings} };
    }
    if ( @{ $self->{statuses} } ) {
        push @lines, '', 'Notifications:';
        push @lines, map {
            '    ' . ( $_->{text} // join( ', ', map { "$_" } sort keys %$_ ) )
        } @{ $self->{statuses} };
    }
    if ( @{ $self->{outcomes} } ) {
        push @lines, '', 'Jobs:';
        foreach my $o ( @{ $self->{outcomes} } ) {
            my $out = $o->{outcome};
            push @lines,
                sprintf( '    %s: %s%s',
                $o->{item}, $out->status, $out->message ? ' - ' . $out->message : '' );
        }
    }

    return join( "\n", @lines ) . "\n";
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
