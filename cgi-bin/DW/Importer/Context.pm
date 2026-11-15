#!/usr/bin/perl
#
# DW::Importer::Context
#
# Everything one import job needs to know about the import it is running.
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

package DW::Importer::Context;

=head1 NAME

DW::Importer::Context - The state of one running import job

=head1 SYNOPSIS

    sub run {
        my ( $class, $ctx ) = @_;
        my $u = $ctx->u;
        $ctx->log( 'Importing for %s', $u->user );
        $ctx->title( 'fetching page %d', $page );
        $ctx->cache->{seen}->{$id} = 1;
        return $ctx->ok;
    }

=head1 DESCRIPTION

A new context is made for every job, so nothing in it can leak from one job to the
next: this is where per-job caches live instead of in package variables.

=head2 Fields

=over

=item C<u>

The local user (journal) being imported into. Undefined only while the job is
reporting that it couldn't be loaded.

=item C<data>

The C<import_data> row: C<userid>, C<import_data_id>, C<hostname>, C<username>,
C<usejournal>, C<password_md5> and C<options> (the thawed hashref of options the user
chose).

=item C<item>

The registry definition of the item this job runs.

=item C<job>, C<class>, C<logger>

The TheSchwartz job, the worker class and the L<DW::Importer::Logger>.

=item C<cache>

A hashref for the job to keep what it has worked out, such as the mapping from remote
to local users.

=back

=cut

use strict;
use warnings;

use DW::Importer::Outcome;

sub new {
    my ( $class, %args ) = @_;
    return bless { cache => {}, %args }, $class;
}

sub u      { $_[0]->{u} }
sub data   { $_[0]->{data} }
sub item   { $_[0]->{item} }
sub job    { $_[0]->{job} }
sub logger { $_[0]->{logger} }
sub cache  { $_[0]->{cache} }

=head2 C<< $ctx->transport >>

The object a source adapter does its network I/O through, if the job was given one
(see L<DW::Importer::Source::LiveJournal::Transport>); undef means the adapter's default.

=cut

sub transport { $_[0]->{transport} }

=head2 C<< $ctx->sink >>

The L<DW::Importer::Sink> the job writes through.

=head2 C<< $ctx->dry_run >>

True if this is a dry run: the sink only records what it would write, and the runner
leaves the item's status, notifications and stats alone.

=cut

sub sink    { $_[0]->{sink} }
sub dry_run { $_[0]->{dry_run} }

=head2 C<< $ctx->options >>

The options the user chose for this import.

=cut

sub options { $_[0]->{data}->{options} || {} }

=head2 C<< $ctx->log( $format, @args ) >>

Writes a line to the job's log.

=cut

sub log {
    my ( $self, @args ) = @_;
    return $self->{logger} ? $self->{logger}->log(@args) : undef;
}

=head2 C<< $ctx->title( [ $format, @args ] ) >>

Sets the process title to say what the job is doing, e.g.
C<content-importer [entries: someone(123) getevents - 1 to 100]>.

=cut

sub title {
    my ( $self, $format, @args ) = @_;

    my $msg = defined $format ? sprintf( $format, @args ) : '';
    $msg = " $msg" if $msg;

    my $u = $self->{u};
    $0 = sprintf(
        'content-importer [%s: %s(%d)%s]',
        $self->{item}->{short_name},
        $u ? $u->user : '?',
        $u ? $u->id   : 0, $msg
    );
}

=head2 C<< $ctx->status( %args ) >>

Sends the user (every maintainer, for a community) a status notification; C<%args> is
what the notification shows, such as C<text>.

=cut

sub status {
    my ( $self, %args ) = @_;

    # nobody is told anything in a dry run; the report says what they would be
    if ( $self->{dry_run} ) {
        $self->{sink}->report->add_status( item => $self->{item}->{name}, %args )
            if $self->{sink}->can('report');
        return;
    }
    return $self->{class}->status( $self->{data}, $self->{item}->{name}, {%args} );
}

=head2 C<< $ctx->ok( %opts ) >>

=head2 C<< $ctx->fail( $format, @args ) >>

=head2 C<< $ctx->temp_fail( $format, @args ) >>

Shorthand for the L<DW::Importer::Outcome> constructors.

=cut

sub ok        { my $self = shift; return DW::Importer::Outcome->ok(@_) }
sub fail      { my $self = shift; return DW::Importer::Outcome->fail(@_) }
sub temp_fail { my $self = shift; return DW::Importer::Outcome->temp_fail(@_) }

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
