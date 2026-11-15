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
message>. A logger can keep the log in L<DW::Importer::LogStore>, write to the TheSchwartz
job's debug output, and/or keep the lines in memory.

A stored log is buffered and written as a chunk each time the buffer passes
C<$DW::Importer::Logger::FLUSH_BYTES> or C<$DW::Importer::Logger::FLUSH_SECONDS> have passed
since the last attempt (checked as lines are logged), and when the logger is closed. Logging
never fails the import: if the log can't be started or a chunk can't be stored, that is
warned about, the lines stay in the buffer for the next attempt, and the buffer is capped at
C<$DW::Importer::Logger::MAX_BUFFER> by dropping its oldest lines for a marker saying so.

=cut

use strict;
use warnings;

use IO::Handle;
use Time::HiRes qw/ gettimeofday tv_interval /;

use DW::Importer::LogStore;

our $FLUSH_BYTES   = 256 * 1024;
our $FLUSH_SECONDS = 30;
our $MAX_BUFFER    = 4 * 1024 * 1024;

sub new {
    my ( $class, %opts ) = @_;
    return bless {
        begin    => [ gettimeofday() ],
        last     => undef,
        fh       => $opts{fh},
        job      => $opts{job},
        store    => $opts{store} ? 1 : 0,
        buffer   => '',
        dropped  => 0,
        lines    => [],
        messages => [],
        keep     => $opts{keep} ? 1 : 0,
    }, $class;
}

=head2 C<< DW::Importer::Logger->for_job( %opts ) >>

The logger for a running job: C<job>, C<userid>, C<import_data_id> and C<item> are
needed. It starts a log in L<DW::Importer::LogStore>; if that fails the job's debug output
is still used, and starting is tried again when the buffer is next flushed.

=cut

sub for_job {
    my ( $class, %opts ) = @_;

    my $self = $class->new( store => 1, job => $opts{job} );
    @{$self}{qw( userid import_data_id item )} = @opts{qw( userid import_data_id item )};
    $self->{buffer}     = "[0.00s 0.00s] Log started at " . LJ::mysql_time( undef, 1 ) . ".\n";
    $self->{last_flush} = time();
    $self->_start;
    return $self;
}

=head2 C<< $logger->logid >>

The id of the log in L<DW::Importer::LogStore>, or undef for a logger that isn't stored or
whose log could not be started.

=cut

sub logid { $_[0]->{logid} }

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
    $self->_buffer($line)      if $self->{store};
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

Writes out what is buffered and closes the file handle, if there is one.

=cut

sub close {
    my ($self) = @_;
    $self->_flush if $self->{store} && !$self->{closed};
    $self->{closed} = 1;
    close $self->{fh} if $self->{fh};
    $self->{fh} = undef;
}

# a logger that is dropped without being closed still writes what it has, if it can
sub DESTROY {
    my ($self) = @_;
    return unless $self->{store} && !$self->{closed};

    local ( $@, $! );
    eval { $self->_flush };
}

# add a line to the buffer and write it out if it is time
sub _buffer {
    my ( $self, $line ) = @_;

    # the stored log is UTF-8 bytes. most of the site passes text around as UTF-8 bytes
    # already, so only a string of characters is encoded; appending one to a buffer of
    # bytes would otherwise re-encode every high byte in it
    utf8::encode($line) if utf8::is_utf8($line);
    $self->{buffer} .= $line;
    $self->_shed if length $self->{buffer} > $MAX_BUFFER;

    my $since = time() - $self->{last_flush};
    if ( $since >= $FLUSH_SECONDS
        || ( length $self->{buffer} >= $FLUSH_BYTES && !$self->{failing} ) )
    {
        $self->_flush;
    }
}

# the store has not been taking chunks, so drop the oldest lines to get back under the cap
sub _shed {
    my ($self) = @_;

    my $excess = length( $self->{buffer} ) - $MAX_BUFFER;
    my $cut    = index( $self->{buffer}, "\n", $excess );
    $cut = length( $self->{buffer} ) - 1 if $cut < 0;

    my $dropped = substr( $self->{buffer}, 0, $cut + 1, '' );
    $self->{dropped} += ( $dropped =~ tr/\n// ) || 1;
}

sub _start {
    my ($self) = @_;
    $self->{logid}   = DW::Importer::LogStore->start( @{$self}{qw( userid import_data_id item )} );
    $self->{failing} = defined $self->{logid} ? 0 : 1;
}

# write the buffer out as one chunk, starting the log first if that has not worked yet. On
# failure the buffer is kept for the next attempt.
sub _flush {
    my ($self) = @_;

    $self->{last_flush} = time();

    $self->_start unless defined $self->{logid};
    return 0 unless defined $self->{logid};

    my $text = $self->{buffer};
    return 1 unless length $text;
    if ( $self->{dropped} ) {
        $text =
            "[$self->{dropped} earlier lines were dropped: the log could not be stored]\n" . $text;
    }

    my $ok = DW::Importer::LogStore->append_chunk( $self->{logid}, $self->{userid},
        $self->{import_data_id}, \$text );
    $self->{failing} = $ok ? 0 : 1;
    if ($ok) {
        $self->{buffer}  = '';
        $self->{dropped} = 0;
    }
    return $ok;
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
