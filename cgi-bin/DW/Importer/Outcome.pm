#!/usr/bin/perl
#
# DW::Importer::Outcome
#
# How an import job says how it ended.
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

package DW::Importer::Outcome;

=head1 NAME

DW::Importer::Outcome - The result of running an import job

=head1 SYNOPSIS

    return DW::Importer::Outcome->ok;
    return DW::Importer::Outcome->temp_fail( 'XMLRPC failure: %s', $error );
    die DW::Importer::Outcome->fail('The password was rejected.');

=head1 DESCRIPTION

A job's C<run> method returns an outcome, or dies with one from anywhere inside it
(including closures that can't return to the top). The job runner turns the outcome
into the item's status, the user's notification and the TheSchwartz job's state.

=over

=item C<ok>

The item finished. Pass C<< show => 0 >> to leave the user's inbox alone.

=item C<temp_fail>

Something went wrong that may go away: the job is retried, until it has failed too
many times and becomes a permanent failure.

=item C<fail>

Something went wrong that retrying won't fix.

=back

Messages are C<sprintf> formats when arguments follow and are used as written
otherwise, so error text from a remote site can be passed straight in.

=cut

use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;
    return bless {%args}, $class;
}

sub ok {
    my ( $class, %opts ) = @_;
    return $class->new( status => 'ok', %opts );
}

sub fail {
    my ( $class, $fmt, @args ) = @_;
    return $class->new( status => 'fail', message => _format( $fmt, @args ) );
}

sub temp_fail {
    my ( $class, $fmt, @args ) = @_;
    return $class->new( status => 'temp_fail', message => _format( $fmt, @args ) );
}

sub _format {
    my ( $fmt, @args ) = @_;
    return @args ? sprintf( $fmt, @args ) : $fmt;
}

=head2 Accessors

C<status> (C<ok>, C<temp_fail> or C<fail>), C<message>, and C<show>: for C<ok>, false
if the user should not be told.

=cut

sub status  { $_[0]->{status} }
sub message { $_[0]->{message} }
sub show    { $_[0]->{show} }

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
