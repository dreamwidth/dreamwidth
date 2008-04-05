#!/usr/bin/perl
##############################################################################

=head1 NAME

dbreportd - Report database latencies at regular intervals.

=head1 SYNOPSIS

  $ dbreportd OPTIONS

=head1 OPTIONS

=over 4

=item -c, --clearscreen

Clear the screen and home the cursor before printing each report, like top. May
not work on all terminals.

=item -d, --debug

Turn on debugging information. May be specified more than once for (potentially)
increased levels of debugging.

=item -h, --help

Output a help message and exit.

=item -i, --interval=SECONDS

Set the number of seconds between reports to SECONDS. Defaults to 3 second
intervals.

=item -p, --port=PORT

Set the port to listen on for reports. This is set in ljconfig.pl, but can be
overridden here.

=item -V, --version

Output version information and exit.

=back

=head1 REQUIRES

I<Token requires line>

=head1 DESCRIPTION

None yet.

=head1 AUTHOR

Michael Granger <ged@FaerieMUD.org>

Copyright (c) 2004 Danga Interactive. All rights reserved.

This program is Open Source software. You may use, modify, and/or redistribute
this software under the terms of the Perl Artistic License. (See
http://language.perl.com/misc/Artistic.html)

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTIBILITY AND
FITNESS FOR A PARTICULAR PURPOSE.

=cut

# :TODO: Change param order in received msgs

##############################################################################
package dbreportd;
use strict;
use warnings qw{all};


###############################################################################
###  I N I T I A L I Z A T I O N
###############################################################################
BEGIN {

    # Turn STDOUT buffering off
    $| = 1;

    # Versioning stuff and custom includes
    use vars qw{$VERSION $RCSID};
    $VERSION    = do { my @r = (q$Revision: 3794 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    $RCSID      = q$Id: ljblockwatcher.pl 3794 2004-03-09 22:25:05Z deveiant $;

    # Define some constants
    use constant TRUE   => 1;
    use constant FALSE  => 0;

    # How many time samples to keep around to determine average latency
    use constant SAMPLE_DEPTH       => 10;

    # How many samples to show in the "top <n> slow queries"
    use constant TOP_QUERY_SIZE     => 5;

    # ANSI vt100 escape codes for various things
    use constant VT100_CLEARSCREEN  => "\e[2J";
    use constant VT100_HOME         => "\e[0;0H";

    # Modules
    use Getopt::Long        qw{GetOptions};
    use Pod::Usage          qw{pod2usage};

    use IO::Socket::INET    qw{};
    use IO::Select          qw{};
    use Time::HiRes         qw{usleep};
    use Data::Dumper        qw{};

    # Turn on option bundling (-vid)
    Getopt::Long::Configure( "bundling" );
}

our $Debug = FALSE;

### Main body
MAIN: {
    my (
        $helpFlag,              # User requested help?
        $versionFlag,           # User requested version info?

        $interval,              # Interval between generated reports
        $port,                  # Port number to listen on

        $msg,                   # The message buffer for reports
        $sock,                  # UDP socket
        $selector,              # IO::Select object
        $lastReport,            # time() of last report output
        $host,                  # Message host
        $time,                  # Message time
        $notes,                 # Message notes
        $type,                  # Operation type (currently unused)
        %buffers,               # SampleBuffers keyed by host
        $clearscreenFlag,       # Clear the screen before every report?
       );

    # Print the program header and read in command line options
    GetOptions(
        'd|debug+'      => \$Debug,
        'h|help'        => \$helpFlag,
        'i|interval=i'  => \$interval,
        'V|version'     => \$versionFlag,
        'p|port=i'      => \$port,
        'c|clearscreen' => \$clearscreenFlag,
       ) or abortWithUsage();

    # If the -h flag or -V flag was given, just show the help or version,
    # respectively, and exit.
    helpMode() and exit if $helpFlag;
    versionMode() and exit if $versionFlag;

    # Either get the port from the command line or a default
    $port ||= 4774;

    # Set the interval to a default if it wasn't specified
    $interval = 3 if !defined $interval;

    # Open a receiving UDP socket
    print VT100_CLEARSCREEN, VT100_HOME if $clearscreenFlag;
    print "Setting up listener on port $port\n";
    $sock = new IO::Socket::INET (
        Proto     => 'udp',
        LocalPort => $port
       ) or die "Failed to open receiving socket: $!";

    $selector = new IO::Select;
    $selector->add( $sock );
    $lastReport = time();

    %buffers = ();

    # Print reports every couple of seconds
    while ( 1 ) {
        if ( $selector->can_read($interval) ) {

            # Get the message and split it back into four parts
            my $addr = $sock->recv( $msg, 1024, 0 );
            print ">>> Message: $msg\n" if $Debug;
            ( $host, $type, $time, $notes ) = split( /\x3/, $msg, 4 );

            # Add the time and notes to the table of hosts
            $buffers{ $host } ||= new SampleBuffer ( $host, depth => SAMPLE_DEPTH );
            $buffers{ $host }->add( $type, $time, $notes );
        } else {
            sleep 0.5;
        }

    } continue {
        if ( (time() - $lastReport) > $interval ) {
            print VT100_CLEARSCREEN, VT100_HOME if $clearscreenFlag;
            print_report( values %buffers );
            $lastReport = time();
        }
    };

}


### FUNCTION: print_report( @buffers )
### Given a list of SampleBuffer objects, print a table with the ones with the
### highest average times.
sub print_report {
    my @buffers = @_;

    my (
        $row,                   # Row count for display
        @top,                   # Top 5 slowest average buffers
        %top,                   # ^-- Hash of same
        @sbuffers,              # Buffer objects sorted by hostname
        @wbuffers,              # Buffer objects sorted by worst op
        $fmt,                   # printf format for report rows
        $prefix,                # Line prefixes
       );

    if ( @buffers ) {
        # Pick the 5 slowest operations
        @top =
            map  { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map  { [$_->host, $_->average_time] }
            @buffers;
        $row = 0;
        %top = ();
        foreach my $host ( @top[0 ... TOP_QUERY_SIZE] ) {
            last unless defined $host;
            $top{$host} = ++$row unless exists $top{$host};
        }
        #print Data::Dumper->Dumpxs( [\%top], ['top'] ), "\n";

        # Make an array of sorted buffer objects by worst average time
        @sbuffers =
            map  { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map  { [$_, $_->average_time] }
            @buffers;

        # Make an array of sorted buffer objects by worst time
        @wbuffers =
            map  { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map  { [$_, $_->worst_time] }
            @buffers;

        # Output all hosts with the average worst operation times
        $fmt = "%-2s%25s %0.5fs";
        $row = 0;
        header( "Average longest blocking operations, by host" );
        foreach my $buf (@sbuffers) {
            $row++;

            if ( exists $top{$buf->host} && $top{$buf->host} <= 3 ) {
                $prefix = '+';
            } else {
                $prefix = ' ';
            }

            printf "$fmt\n", $prefix, $buf->host, $buf->average_time;
        }
        print "\n";

        # Output the worst operations with their notes
        $row = 0;
        $fmt = "%0.5fs: '%s' [%s/%s]\n";
        header( "%d worst blockers", TOP_QUERY_SIZE );
        foreach my $buf (@wbuffers[0 ... TOP_QUERY_SIZE]) {
            last unless defined $buf;
            $row++;

            my $sample = $buf->worst_sample;
            printf( $fmt,
                    $sample->time,
                    $sample->notes || "(none)",
                    $sample->type,
                    $buf->host );
        }
        print "\n";

        # Print the raw buffer objects if debugging
        if ( $Debug ) {
            header( "Raw buffers" );
            foreach my $buf ( @buffers ) {
                local $Data::Dumper::Indent = 0;
                local $Data::Dumper::Terse = TRUE;
                print Data::Dumper->Dumpxs( [$buf], ['buf'] ), "\n";
            }
        }

        print "\n";
    }

    else {
        print "No hosts reporting.\n";
    }
}


### FUNCTION: header( $fmt, @args )
### Printf the given message as a header.
sub header {
    my ( $fmt, @args ) = @_;
    my $msg = sprintf( $fmt, @args );
    chomp( $msg );

    print "$msg\n", '-' x 75, "\n";
}


### FUNCTION: helpMode()
### Exit normally after printing the usage message
sub helpMode {
    pod2usage( -verbose => 1, -exitval => 0 );
}


### FUNCTION: versionMode()
### Exit normally after printing version information
sub versionMode {
    print STDERR "dbreportd $VERSION\n";
    exit;
}


### FUNCTION: abortWithUsage()
### Abort the program showing usage message.
sub abortWithUsage {
    if ( @_ ) {
        pod2usage( -verbose => 1, -exitval => 1, -msg => join('', @_) );
    } else {
        pod2usage( -verbose => 1, -exitval => 1 );
    }
}


### FUNCTION: abort( @messages )
### Print the specified messages to the terminal and exit with a non-zero status.
sub abort {
    my $msg = @_ ? join '', @_ : "unknown error";
    print STDERR $msg, "\n";
    exit 1;
}



#####################################################################
### T I M E   S A M P L E   C L A S S
#####################################################################
package Sample;
use strict;

BEGIN {
    use vars qw{$AUTOLOAD};
    use Carp qw{croak confess};
    use Data::Dumper ();
    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
}

### METHOD: new( $host )
### Create a new sample buffer for the given host
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {
        type    => 'db',
        time    => 0.0,
        notes   => '',
    }, $class;

    if ( @_ && (@_ % 2 == 0) ) {
        my %args = @_;
        foreach my $meth ( keys %args ) {
            $self->$meth( $args{$meth} );
        }
    }

    return $self;
}



### FUNCTION: blessed( $var )
### Returns a true value if the given value is a blessed reference.
sub blessed {
    my $arg = shift;
    return ref $arg && UNIVERSAL::isa( $arg, 'UNIVERSAL' );
}


### (PROXY) METHOD: AUTOLOAD( @args )
### Proxy method to build (non-translucent) object accessors.
sub AUTOLOAD {
    my $self = shift;
    confess "Cannot be called as a function" unless $self && blessed $self;

    ( my $name = $AUTOLOAD ) =~ s{.*::}{};

    ### Build an accessor for extant attributes
    if ( exists $self->{$name} ) {

        ### Define an accessor for this attribute
        my $method = sub {
            my $closureSelf = shift or confess "Cannot be called as a function";
            $closureSelf->{$name} = shift if @_;
            return $closureSelf->{$name};
        };

        ### Install the new method in the symbol table
      NO_STRICT_REFS: {
            no strict 'refs';
            *{$AUTOLOAD} = $method;
        }

        ### Now jump to the new method after sticking the self-ref back onto the
        ### stack
        unshift @_, $self;
        goto &$AUTOLOAD;
    }

    ### Try to delegate to our parent's version of the method
    my $parentMethod = "SUPER::$name";
    return $self->$parentMethod( @_ );
}

sub DESTROY {}
sub END {}



#####################################################################
### S A M P L E B U F F E R   C L A S S
#####################################################################

### Class for tracking latencies for a given host
package SampleBuffer;
use strict;

BEGIN {
    use Carp qw{croak confess};
    use vars qw{$AUTOLOAD};
}


### METHOD: new( $host )
### Create a new sample buffer for the given host
sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $host = shift or die "No hostname given";

    my $self = bless {
        host    => $host,
        samples => {},
        depth   => 10,
       }, $class;

    if ( @_ && (@_ % 2 == 0) ) {
        my %args = @_;
        foreach my $meth ( keys %args ) {
            $self->$meth( $args{$meth} );
        }
    }

    return $self;
}


### METHOD: add( $type, $time, $notes )
### Add the specified I<time> to the sample buffer for the given I<type> with
### the given I<notes>.
sub add {
    my $self = shift or confess "Cannot be called as a function";
    my ( $type, $time, $notes ) = @_;

    $self->{samples}{ $type } ||= [];
    my $slist = $self->{samples}{ $type };

    my $sample = new Sample ( type => $type, time => $time, notes => $notes );
    unshift @$slist, $sample;
    pop @$slist if @$slist > $self->{depth};

    return scalar @$slist;
}


### METHOD: samples( [$type] )
### Fetch a list of the samples of the given I<type> in the buffer, or a list of
### all samples if I<type> is not specified.
sub samples {
    my $self = shift or confess "Cannot be used as a function";
    my $type = shift;

    my @samples = ();

    # Gather the samples that are going to be used to make the average, either
    # the specific kind requested, or all of 'em.
    if ( $type ) {
        # Regexp filter
        if ( ref $type eq 'Regexp' ) {
            foreach my $key ( keys %{$self->{samples}} ) {
                push @samples, @{$self->{samples}{ $key }}
                    if $type =~ $key;
            }
        }

        # Any other filter just gets string-equalled.
        else {
            @samples = @{$self->{samples}{ $type }};
        }
    } else {
        foreach my $type ( keys %{$self->{samples}} ) {
            push @samples, @{$self->{samples}{ $type }};
        }
    }

    return @samples;
}


### METHOD: average_time( [$type] )
### Return the average of all the times currently in the buffer for the given
### I<type>. If I<type> isn't given, returns the overall average.
sub average_time {
    my $self = shift or confess "Cannot be used as a function";
    my $type = shift;

    my ( $time, $count ) = ( 0, 0 );

    # Now add and count all the time from each target sample
    foreach my $sample ( $self->samples($type) ) {
        $time += $sample->time;
        $count++;
    }

    return $time / $count;
}


### METHOD: worst_sample( [$type] )
### Return the worst sample in the buffer for the given I<type>. If no type is
### given, return the worst overall sample.
sub worst_sample {
    my $self = shift or confess "Cannot be used as a function";
    my $type = shift;
    return () unless %{$self->{samples}};

    my @samples =
        map  { $_->[0] }
        sort { $a->[1] <=> $b->[1] }
        map  { [$_, $_->time] } $self->samples( $type );

    return $samples[-1];
}


### METHOD: worst_time( [$type] )
### Return the worst time in the buffer for the given I<type>. If no I<type> is
### given, returns the worst overall time.
sub worst_time {
    my $self = shift or confess "Cannot be used as a function";
    my $type = shift;

    my $samp = $self->worst_sample( $type ) or return ();
    return $samp->time;
}


### METHOD: worst_notes( [$type] )
### Return the notes from the worst sample in the buffer for the given
### I<type>. If I<type> is not specified, returns the notes for the worst
### overall sample.
sub worst_notes {
    my $self = shift or confess "Cannot be used as a function";
    my $type = shift;

    my $samp = $self->worst_sample( $type ) or return ();
    return $samp->notes;
}


### FUNCTION: blessed( $var )
### Returns a true value if the given value is a blessed reference.
sub blessed {
    my $arg = shift;
    return ref $arg && UNIVERSAL::isa( $arg, 'UNIVERSAL' );
}


### (PROXY) METHOD: AUTOLOAD( @args )
### Proxy method to build (non-translucent) object accessors.
sub AUTOLOAD {
    my $self = shift;
    confess "Cannot be called as a function" unless $self && blessed $self;

    ( my $name = $AUTOLOAD ) =~ s{.*::}{};

    ### Build an accessor for extant attributes
    if ( exists $self->{$name} ) {

        ### Define an accessor for this attribute
        my $method = sub {
            my $closureSelf = shift or confess "Cannot be called as a function";
            $closureSelf->{$name} = shift if @_;
            return $closureSelf->{$name};
        };

        ### Install the new method in the symbol table
      NO_STRICT_REFS: {
            no strict 'refs';
            *{$AUTOLOAD} = $method;
        }

        ### Now jump to the new method after sticking the self-ref back onto the
        ### stack
        unshift @_, $self;
        goto &$AUTOLOAD;
    }

    ### Try to delegate to our parent's version of the method
    my $parentMethod = "SUPER::$name";
    return $self->$parentMethod( @_ );
}

sub DESTROY {}
sub END {}


