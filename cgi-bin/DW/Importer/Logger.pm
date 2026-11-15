#!/usr/bin/perl
#
# DW::Importer::Logger
#
# The log an import job writes for the people debugging it.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::Logger;

=head1 NAME

DW::Importer::Logger - Timestamped log lines for import jobs

=head1 SYNOPSIS

    my $logger = DW::Importer::Logger->for_job( job => $job, userid => $uid,
        import_data_id => $impid, item => 'lj_entries' );
    $logger->log( 'Fetched %d entries.', $count );

    my $test_logger = DW::Importer::Logger->in_memory;
    $test_logger->log('something');
    is_deeply( [ $test_logger->messages ], ['something'] );

=head1 DESCRIPTION

Every line is written as C<[seconds since the last line, seconds since the log began]
message>. A logger can write to a file for the import
(C<$LJ::HOME/logs/imports/E<lt>useridE<gt>/E<lt>import idE<gt>.E<lt>itemE<gt>.E<lt>pidE<gt>>),
to the TheSchwartz job's debug output, and/or keep the lines in memory.

=cut

use strict;
use warnings;

use IO::Handle;
use Time::HiRes qw/ gettimeofday tv_interval /;

sub new {
    my ( $class, %opts ) = @_;
    return bless {
        begin    => [ gettimeofday() ],
        last     => undef,
        fh       => $opts{fh},
        job      => $opts{job},
        lines    => [],
        messages => [],
        keep     => $opts{keep} ? 1 : 0,
    }, $class;
}

=head2 C<< DW::Importer::Logger->for_job( %opts ) >>

The logger for a running job: C<job>, C<userid>, C<import_data_id> and C<item> are
needed. If the log file can't be created the job's debug output is still used.

=cut

sub for_job {
    my ( $class, %opts ) = @_;

    my $fh;
    my $dir = "$LJ::HOME/logs/imports/$opts{userid}";
    mkdir "$LJ::HOME/logs/imports";
    mkdir $dir;
    if ( open $fh, '>>', "$dir/$opts{import_data_id}.$opts{item}.$$" ) {
        $fh->autoflush(1);
        print $fh "[0.00s 0.00s] Log started at " . LJ::mysql_time( undef, 1 ) . ".\n";
    }
    else {
        $fh = undef;
    }

    return $class->new( fh => $fh, job => $opts{job} );
}

=head2 C<< DW::Importer::Logger->in_memory( [ job => $job ] ) >>

A logger that keeps what it is given (and still passes it to the job's debug output),
for tests.

=cut

sub in_memory {
    my ( $class, %opts ) = @_;
    return $class->new( keep => 1, job => $opts{job} );
}

=head2 C<< $logger->log( $format, @args ) >>

Writes one line; the format is only used as a C<sprintf> format when arguments are given.
Always returns undef.

=cut

sub log {
    my ( $self, $format, @args ) = @_;

    $self->{last} ||= [ gettimeofday() ];

    # callers log values that may be undefined, such as a map lookup that found nothing
    no warnings 'uninitialized';
    my $message = @args ? sprintf( $format, @args ) : $format;
    my $line    = sprintf(
        "[%0.4fs %0.1fs] %s\n",
        tv_interval( $self->{last} ),
        tv_interval( $self->{begin} ), $message
    );

    $self->{fh}->print($line)  if $self->{fh};
    $self->{job}->debug($line) if $self->{job};
    if ( $self->{keep} ) {
        push @{ $self->{lines} },    $line;
        push @{ $self->{messages} }, $message;
    }

    $self->{last} = [ gettimeofday() ];
    return undef;
}

=head2 C<< $logger->lines >>

=head2 C<< $logger->messages >>

For an in-memory logger, what was logged, with and without the timestamps.

=cut

sub lines    { @{ $_[0]->{lines} } }
sub messages { @{ $_[0]->{messages} } }

=head2 C<< $logger->close >>

Closes the log file.

=cut

sub close {
    my ($self) = @_;
    close $self->{fh} if $self->{fh};
    $self->{fh} = undef;
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
