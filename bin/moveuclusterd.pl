#!/usr/bin/perl
##############################################################################
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

=head1 NAME

moveuclusterd - User-mover task coordinater daemon

=head1 SYNOPSIS

  $ moveuclusterd OPTIONS

=head2 OPTIONS

=over 4

=item -d, --debug

Output debugging information in addition to normal progress messages. May be
specified more than once to increase debug level.

=item -D, --daemon

Background the program.

=item -h, --help

Output a help message and exit.

=item -H, --host=HOST

Listen on the specified I<HOST> instead of the default '0.0.0.0'.

=item -m, --maxlocktime=SECONDS

Set the number of seconds that is targeted as the timespan to keep jobs locked
before assigning them. If the oldest job in a cluster's queue is older than this
value (120 by default), no users will be locked for that queue until the next
check.

=item -p, --port=PORT

Listen to the given I<PORT> instead of the default 2789.

=item -r, --defaultrate=INTEGER

Set the default rate limit for any source cluster which has not had its rate set
to I<INTEGER>. The default rate is 1.

=item -s, --lockscale=INTEGER

Set the lock-scaling factor to I<INTEGER>. The lock scaling factor is used to
decide how many users to lock per source cluster; a scaling factor of C<3> (the
default) would cause the jobserver to try to maintain 3 x the number of jobs as
there are allowed connections for a given cluster, modulo the C<maxlocktime>.

=item -v, --verbose

Output the jobserver's log to STDERR.

=back

=head1 REQUIRES

I<Token requires line>

=head1 DESCRIPTION

None yet.

=head1 AUTHOR

Michael Granger E<lt>ged@danga.comE<gt>

Copyright (c) 2004 Danga Interactive. All rights reserved.

This module is free software. You may use, modify, and/or redistribute this
software under the terms of the Perl Artistic License. (See
http://language.perl.com/misc/Artistic.html)

=cut

##############################################################################
package moveuclusterd;
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
    $VERSION = do { my @r = ( q$Revision: 12350 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r };
    $RCSID   = q$Id: moveuclusterd.pl 12350 2007-08-28 22:20:25Z ahassan $;

    # Define some constants
    use constant TRUE  => 1;
    use constant FALSE => 0;

    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

    # Modules
    use Carp qw{croak confess};
    use Getopt::Long qw{GetOptions};
    use Pod::Usage qw{pod2usage};

    Getopt::Long::Configure('bundling');
}

###############################################################################
### C O N F I G U R A T I O N   G L O B A L S
###############################################################################

### Main body
sub MAIN {
    my (
        $debugLevel,     # Debugging level to set in server
        $helpFlag,       # User requested help?
        $daemonFlag,     # Background after starting?
        $defaultRate,    # Default src cluster rate cmdline setting
        $verboseFlag,    # Output the log or no?
        $server,         # JobServer object
        %config,         # JobServer configuration
        $port,           # Port to listen on
        $host,           # Address to listen on
        $lockScale,      # Lock scaling factor
        $maxLockTime,    # Max time to keep users locked
    );

    # Print the program header and read in command line options
    GetOptions(
        'D|daemon'        => \$daemonFlag,
        'H|host=s'        => \$host,
        'd|debug+'        => \$debugLevel,
        'h|help'          => \$helpFlag,
        'm|maxlocktime=i' => \$maxLockTime,
        'p|port=i'        => \$port,
        'r|defaultrate=i' => \$defaultRate,
        's|lockscale=i'   => \$lockScale,
        'v|verbose'       => \$verboseFlag,
    ) or abortWithUsage();

    # If the -h flag was given, just show the usage and quit
    helpMode() and exit if $helpFlag;

    # Build the configuration hash
    $config{host} = $host if $host;
    $config{port} = $port if $port;
    $config{daemon}      = $daemonFlag;
    $config{debugLevel}  = $debugLevel || 0;
    $config{defaultRate} = $defaultRate if $defaultRate;
    $config{lockScale}   = $lockScale if $lockScale;
    $config{maxLockTime} = $maxLockTime if defined $maxLockTime;

    # Create a new daemon object
    $server = new JobServer(%config);

    # Add a simple log handler if they've requested verbose output
    if ($verboseFlag) {
        my $tmplogger = sub {
            my ( $level, $msg ) = @_;
            print STDERR "[$level] $msg\n";
        };
        $server->addHandler( 'log', 'verboselogger', $tmplogger );
    }

    # Start the server
    $server->start();
}

### FUNCTION: helpMode()
### Exit normally after printing the usage message
sub helpMode {
    pod2usage( -verbose => 1, -exitval => 0 );
}

### FUNCTION: abortWithUsage( $message )
### Abort the program showing usage message.
sub abortWithUsage {
    my $msg = @_ ? join( '', @_ ) : "";

    if ($msg) {
        pod2usage( -verbose => 1, -exitval => 1, -message => "$msg" );
    }
    else {
        pod2usage( -verbose => 1, -exitval => 1 );
    }
}

### If run from the command line, run the server.
if ( $0 eq __FILE__ ) { MAIN() }

#####################################################################
###	T I M E D   B U F F E R   C L A S S
#####################################################################
package TimedBuffer;

BEGIN {
    use Carp qw{croak confess};
}

our $DefaultExpiration = 120;

### (CONSTRUCTOR) METHOD: new( $seconds )
### Create a new timed buffer which will remove entries the specified number of
### I<seconds> after being added.
sub new {
    my $proto   = shift;
    my $class   = ref $proto || $proto;
    my $seconds = shift || $DefaultExpiration;

    my $self = bless {
        buffer  => [],
        seconds => $seconds,
    }, $class;

    return $self;
}

### METHOD: add( @items )
### Add the given I<items> to the buffer, shifting off older ones if they are
### expired.
sub add {
    my $self  = shift or confess "Cannot be used as a function";
    my @items = @_;

    my $expiration = time - $self->{seconds};
    my $buffer     = $self->{buffer};

    # Expire old entries and add the new ones
    @$buffer = grep { $_->[1] > $expiration } @$buffer;
    push @$buffer, map { [ $_, time ] } @items;

    return scalar @$buffer;
}

### METHOD: get( [@indices] )
### Return the items in the buffer at the specified I<indices>, or all items in
### the buffer if no I<indices> are given.
sub get {
    my $self = shift or confess "Cannot be used as a function";

    my $expiration = time - $self->{seconds};
    my $buffer     = $self->{buffer};

    # Expire old entries
    @$buffer = grep { $_->[1] > $expiration } @$buffer;

    # Return just the values from the buffer, either in a slice if they
    # specified indexes, or the whole thing if not.
    if (@_) {
        return map { $_->[0] } @{$buffer}[@_];
    }
    else {
        return map { $_->[0] } @$buffer;
    }
}

#####################################################################
### D A E M O N   C L A S S
#####################################################################
package JobServer;

BEGIN {
    use IO::Socket qw{};
    use Data::Dumper qw{Dumper};
    use Carp qw{croak confess};
    use Time::HiRes qw{gettimeofday tv_interval};
    use POSIX qw{};

    use fields (
        'clients',        # Connected client objects
        'config',         # Configuration hash
        'listener',       # The listener socket
        'handlers',       # Client event handlers
        'jobs',           # Mover jobs
        'totaljobs',      # Count of jobs processed
        'assignments',    # Jobs that have been assigned
        'users',          # Users in the queue
        'ratelimits',     # Cached cluster ratelimits
        'raterules',      # Rules for building ratelimit table
        'jobcounts',      # Counts per cluster of running jobs
        'starttime',      # Server startup epoch time
        'recentmoves',    # Timed buffer of recently-completed jobs
    );

    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

    use base qw{fields};
}

### Class globals

# Default configuration
our ( %DefaultConfig, %LogLevels );

INIT {

    # Default server configuration; this is merged with any config args the user
    # specifies in the call to the constructor. Most of these correspond with
    # command-line flags, so see that section of the POD header for more
    # information.
    %DefaultConfig = (
        port        => 2789,         # Port to listen on
        host        => '0.0.0.0',    # Host to bind to
        listenQueue => 5,            # Listen queue depth
        daemon      => 0,            # Daemonize or not?
        debugLevel  => 0,            # Debugging log level
        defaultRate => 1,            # The default src cluster rate
        lockScale   => 3,            # Scaling factor for locking users
        maxLockTime => 120,          # Max seconds to keep users locked
    );

    my $level = 0;
    %LogLevels = map { $_ => $level++, } qw{debug info notice warn crit fatal};

    $Data::Dumper::Terse  = 1;
    $Data::Dumper::Indent = 1;
}

#
# Datastructures of class members:
#
# clients:     Hashref of connected clients, keyed by fdno
#
# jobs:        A hash of arrays of JobServer::Job objects:
#              {
#                <srcclusterid> => [ $job1, $job2, ... ],
#                ...
#              }
#
# users:       A hash index into the inner arrays of 'jobs', keyed by
#              userid.
#
# assignments: A hash of arrays; when a job is assigned to a mover, the
#              corresponding JobServer::Job is moved into this hash,
#              keyed by the fdno of the mover responsible.
#
# handlers:    Hash of hashes; this is used to register callbacks for clients that
#              want to monitor the server, receiving log or debugging messages,
#              new job notifications, etc.
#
# totaljobs:   Count of total jobs added to the daemon.
#
# raterules:   Maximum number of jobs which can be run against source clusters,
#              keyed by clusterid. If a global rate limit has been set, this
#              hash also contains a special key 'global' to contain it.
#
# ratelimits:  Cached ratelimits for clusters -- this is rebuilt whenever a
#              ratelimit rule is added, and is partially rebuilt when new jobs
#              are added.
#
# jobcounts:   Count of jobs running against source clusters, keyed by
#              source clusterid.

### (CONSTRUCTOR) METHOD: new( %config )
### Create a new JobServer object with the given I<config>.
sub new {
    my JobServer $self = shift;
    my %config = @_;

    $self = fields::new($self) unless ref $self;

    # Client and job queues
    $self->{clients}     = {};    # fd => client obj
    $self->{jobs}        = {};    # pending jobs: srcluster => [ jobs ]
    $self->{users}       = {};    # by-userid hash of jobs
    $self->{assignments} = {};    # fd => job object
    $self->{totaljobs}   = 0;     # Count of total jobs added
    $self->{raterules}   = {};    # User-set rate-limit rules
    $self->{ratelimits}  = {};    # Cached rate limits by srcclusterid
    $self->{jobcounts}   = {};    # Count of jobs by srcclusterid

    # Create a timed buffer to contain the jobs which have completed in the last
    # 6 minutes.
    $self->{recentmoves} = new TimedBuffer 360;

    # Merge the user-specified configuration with the defaults, with the user's
    # overriding.
    $self->{config} = { %DefaultConfig, %config, };    # merge

    # These two get set by start()
    $self->{listener}  = undef;
    $self->{starttime} = undef;

    # CODE refs for handling various events. Keyed by event name, each subhash
    # contains registrations for event callbacks. Each subhash is keyed by the
    # fdno of the client that requested it, or an arbitrary string if the
    # handler belongs to something other than a client.
    $self->{handlers} = {
        debug => {},
        log   => {},
    };

    return $self;
}

### METHOD: start()
### Start the event loop.
sub start {
    my JobServer $self = shift;

    # Start the listener socket
    my $listener = new IO::Socket::INET
        Proto     => 'tcp',
        LocalAddr => $self->{config}{host},
        LocalPort => $self->{config}{port},
        Listen    => $self->{config}{listenQueue},
        ReuseAddr => 1,
        Blocking  => 0
        or die "new socket: $!";

    # Log the server startup, then daemonize if it's called for
    $self->logMsg( 'notice', "Server listening on %s:%d\n",
        $listener->sockhost, $listener->sockport );
    $self->{listener} = $listener;
    $self->daemonize if $self->{config}{daemon};

    # Remember the startup time
    $self->{starttime} = time;

    # I don't understand this design -- the Client class is where the event loop
    # is? Weird. Thanks to SPUD, though, for the example code.
    JobServer::Client->OtherFds( $listener->fileno => sub { $self->createClient } );
    JobServer::Client->EventLoop();

    return 1;
}

### METHOD: createClient( undef )
### Listener socket readable callback. Accepts a new client socket and wraps a
### JobServer::Client around it.
sub createClient {
    my JobServer $self = shift;

    my (
        $csock,     # Client socket
        $client,    # JobServer::Client object
        $fd,        # File descriptor for client
    );

    # Get the client socket and set it nonblocking
    $csock = $self->{listener}->accept or return;
    $csock->blocking(0);
    $fd = fileno($csock);

    $self->logMsg( 'info', 'Client %d connect: %s:%d', $fd, $csock->peerhost, $csock->peerport );

    # Wrap a client object around it, tell it to watch for input, and send the
    # greeting.
    $client = JobServer::Client->new( $self, $csock );
    $client->watch_read(1);
    $client->write("Ready.\r\n");

    return $self->{clients}{$fd} = $client;
}

### METHOD: disconnectClient( $client=JobServer::Client[, $requeue] )
### Disconnect the specified I<client> from the server. If I<requeue> is true,
### the job belonging to the client (if any) will be put back into the queue of
### pending jobs.
sub disconnectClient {
    my JobServer $self = shift;
    my ( $client, $requeue ) = @_;

    my (
        $csock,    # Client socket
        $fd,       # Client's fdno
        $job,      # Job that client was working on
    );

    # Stop further input from the socket
    $csock = $client->sock;
    $csock->shutdown(0) if $csock->connected;
    $fd = fileno($csock);
    $self->logMsg( 'info', "Client %d disconnect: %s:%d", $fd, $csock->peerhost, $csock->peerport );

    # Remove any event handlers registered for the client
    $self->removeHandlerFromAll($fd);
    $self->unassignJobForClient($fd);

    # Remove the client from our list
    delete $self->{clients}{$fd};
}

### METHOD: clients( undef )
### Get the list of clients (JobServer::Client objects) currently connected to
### the server.
sub clients {
    my JobServer $self = shift;
    return values %{ $self->{clients} };
}

### METHOD: raterules( undef )
### Get the hash of rate rules the server uses to calculate a cluster's
### maximum number of clients.
sub raterules {
    my JobServer $self = shift;
    return %{ $self->{raterules} };
}

### METHOD: recentmoves( undef )
### Get the JobServer::Job objects in the server's "recently-moved" timedbuffer.
sub recentmoves {
    my JobServer $self = shift;
    return $self->{recentmoves}->get;
}

### METHOD: defaultRate( undef )
### Get the default cluster rate as set on the command line.
sub defaultRate {
    my JobServer $self = shift;
    return $self->{config}->{defaultRate};
}

### METHOD: addJobs( @jobs=JobServer::Job )
### Add a job to move the user with the given I<userid> to the cluster with the
### specified I<dstclustid>.
sub addJobs {
    my JobServer $self = shift;
    my @jobs = @_;

    my (
        @responses,      # Inline responses
        $clusterid,      # Cluster iterator
        $job,            # Job object iterator
        $userid,         # User id for user to move
        $newJobCount,    # Count of jobs added to the queue
    );

    $newJobCount = 0;

    # Iterate over job specifications
JOB: for ( my $i = 0 ; $i <= $#jobs ; $i++ ) {
        $job = $jobs[$i];
        $self->debugMsg( 5, "Adding job: %s", $job->stringify );

        ( $userid, $clusterid ) = ( $job->userid, $job->srcclusterid );

        # Check to be sure this job isn't already queued or in progress.
        if ( $self->{users}{$userid} ) {
            $self->debugMsg( 2, "Request for duplicate job %s", $job->stringify );
            $responses[$i] = "Duplicate job for userid $userid";
            next JOB;
        }

        # Queue the job and point the user index at it.
        $self->{jobs}{$clusterid} ||= [];
        push @{ $self->{jobs}{$clusterid} }, $job;
        $self->{users}{$userid} = $job;
        $self->{jobcounts}{$clusterid} ||= 0;

        $responses[$i] = "Added job " . ++$self->{totaljobs};
        $newJobCount++;
    }

    # we might've learned some new clusterids
    %{ $self->{ratelimits} } = ();

    # Scan the task table for users to lock and then send notifications to
    # anyone who's waiting on new jobs if there were any added.
    $self->prelockSomeUsers;
    $self->handleEvent( 'add', $newJobCount ) if $newJobCount;

    return @responses;
}

### METHOD: prelockSomeUsers( undef )
### Mark some of the users in the queues as read-only so the movers don't need
### to do so before moving. Only marks a portion of each queue so as to not
### inconvenience users.
sub prelockSomeUsers {
    my JobServer $self = shift;

    my $start = [ gettimeofday() ];

    my (
        $jobcount,       # Number of jobs queued for a cluster
        $rate,           # Rate for the cluster in question
        $target,         # Number of queued jobs we'd like to be locked
        $lockcount,      # Number of users locked
        $scale,          # Lock scaling factor
        $maxLockTime,    # Max number of seconds to keep users locked
        $clients,        # Number of currently-connected clients
        $jobs,           # Job queue per cluster
    );

    # Twiddle some database bits out in magic voodoo land
    LJ::start_request();

    # Set the scaling factor -- this is a command-line setting that affects how
    # deep the queue is locked per source cluster.
    $scale       = $self->{config}{lockScale};
    $maxLockTime = $self->{config}{maxLockTime};

    $self->debugMsg( 3, "Prelocking with scale: $scale, maxlocktime: $maxLockTime" );

    # Iterate over all the queues we have by cluster
CLUSTER: foreach my $clusterid ( keys %{ $self->{jobs} } ) {
        $rate   = $self->getClusterRateLimit($clusterid);
        $target = $rate * $scale;

        # Now iterate partway into the queue of jobs for the cluster, locking
        # some users if there are some that need locking
        $jobs = $self->{jobs}{$clusterid};
    JOB: for ( my $i = 0 ; $i <= $target ; $i++ ) {

            # If there are fewer jobs than the target number to be locked, or
            # the current job is older than the maximum number of seconds to
            # keep a user locked, skip to the next cluster
            next CLUSTER if $i > $#$jobs;
            next CLUSTER if $jobs->[$i]->secondsSinceLock > $maxLockTime;

            # Skip jobs that are already prelocked. If locking fails, assume
            # there's some database problem and don't try to prelock any more
            # until next time.
            next JOB if $jobs->[$i]->isPrelocked;
            $jobs->[$i]->prelock or last CLUSTER;
        }
    }

    $self->debugMsg( 4, "Prelock time: %0.5fs", tv_interval($start) );
    return $lockcount;
}

### METHOD: getClusterRateLimit( $clusterid )
### Return the number of connections which can be reading from the cluster with
### the given I<clusterid>.
sub getClusterRateLimit {
    my JobServer $self = shift;
    my $clusterid = shift or confess "No clusterid";

    # Swap the next two lines to make the 'global' rate override those of
    # specific clusters.
    return $self->{raterules}{$clusterid} if exists $self->{raterules}{$clusterid};
    return $self->{raterules}{global} if exists $self->{raterules}{global};
    return $self->{config}{defaultRate};
}

### METHOD: getClusterRateLimits( undef )
### Return the rate limits for all known clusters as a hash (or hashref if
### called in scalar context) keyed by clusterid.
sub getClusterRateLimits {
    my JobServer $self = shift;

    # (Re)build the rates table as necessary
    unless ( %{ $self->{ratelimits} } ) {
        for my $clusterid ( keys %{ $self->{jobs} } ) {
            $self->{ratelimits}{$clusterid} =
                $self->getClusterRateLimit($clusterid);
        }
    }

    return wantarray ? %{ $self->{ratelimits} } : $self->{ratelimits};
}

### METHOD: setClusterRateLimit( $clusterid, $rate )
### Set the rate limit for the cluster with the given I<clusterid> to I<rate>.
sub setClusterRateLimit {
    my JobServer $self = shift;
    my ( $clusterid, $rate ) = @_;

    die "No clusterid" unless $clusterid;
    die "No ratelimit" unless defined $rate && int($rate) == $rate;

    # Set the new rule and trash the precalculated table
    $self->{raterules}{$clusterid} = $rate;
    %{ $self->{ratelimits} } = ();

    return "Rate limit for cluster $clusterid set to $rate";
}

### METHOD: setGlobalRateLimit( $rate )
### Set the rate limit for clusters that don't have an explicit ratelimit to
### I<rate>.
sub setGlobalRateLimit {
    my JobServer $self = shift;
    my $rate = shift;
    die "No ratelimit" unless defined $rate && int($rate) == $rate;

    # Set the global rule and clear out the cached table to rebuild it next time
    # it's used
    $self->{raterules}{global} = $rate;
    %{ $self->{ratelimits} } = ();

    return "Global rate limit set to $rate";
}

### METHOD: resetClusterRateLimit( $clusterid )
### Remove the explicit rate limit for the cluster with the given
### I<clusterid>. Returns the new limit for the cluster after resetting.
sub resetClusterRateLimit {
    my JobServer $self = shift;
    my $clusterid = shift or croak "No clusterid given.";

    $self->debugMsg( 1, "Resetting rate limit for cluster $clusterid." );
    delete $self->{raterules}{$clusterid};
    %{ $self->{ratelimits} } = ();

    return $self->{raterules}{global} || $self->{config}{defaultRate};
}

### METHOD: resetGlobalRateLimit( undef )
### Reset the rate limit for clusters that don't have an explicit ratelimit back
### to the default and returns it.
sub resetGlobalRateLimit {
    my JobServer $self = shift;
    delete $self->{raterules}{global};
    %{ $self->{ratelimits} } = ();

    return $self->{config}{defaultRate};
}

### METHOD: getJob( $client=JobServer::Client )
### Fetch a job for the given I<client> and return it. If there are no pending
### jobs, returns the undefined value.
sub getJob {
    my JobServer $self = shift;
    my ($client) = @_ or confess "No client object";

    my (
        $fd,     # Client's fdno
        $job,    # Job arrayref
    );

    $fd = $client->fdno or confess "No file descriptor?!?";
    $self->unassignJobForClient($fd);

    return $self->assignNextJob($fd);
}

### METHOD: assignNextJob( $fdno )
### Find the next pending job from the queue that would read from a non-busy
### source cluster, as determined by the rate limits given to the server. If one
### is found, assign it to the client associated with the given file descriptor
### I<fdno>. Returns the reply to be sent to the client.
sub assignNextJob {
    my JobServer $self = shift;
    my $fd = shift or return;

    my (
        $src,           # Clusterid of a source
        $rates,         # Rate limits by clusterid
        $jobcounts,     # Counts of current jobs, by clusterid
        @candidates,    # Clusters with open slots
    );

    $rates     = $self->getClusterRateLimits;
    $jobcounts = $self->{jobcounts};

    # Find clusterids of clusters with open slots, returning the undefined value
    # if there are none.
    @candidates = grep { $jobcounts->{$_} < $rates->{$_} } keys %{ $self->{jobs} };
    return undef unless @candidates;

    # Pick a random cluster from the available list
    $src = $candidates[ int rand(@candidates) ];
    $self->debugMsg(
        4, "Assigning job for cluster %d (%d of %d)",
        $src, $jobcounts->{$src} + 1,
        $rates->{$src}
    );

    # Assign the next job from that cluster and return it
    return $self->assignJobFromCluster( $src, $fd );
}

### METHOD: assignJobFromCluster( $clusterid, $fdno )
### Assign the next job from the cluster with the specified I<clusterid> to the
### client with the given file descriptor I<fdno>.
sub assignJobFromCluster {
    my JobServer $self = shift;
    my ( $clusterid, $fdno ) = @_;

    # Grab a job from the cluster's queue and add it to the assignments table.
    my $job = $self->{assignments}{$fdno} = shift @{ $self->{jobs}{$clusterid} };
    $job->setFetchtime;

    # Increment the job counter for that cluster and delete the queue if it's
    # empty.
    delete $self->{jobs}{$clusterid} if !@{ $self->{jobs}{$clusterid} };
    $self->{jobcounts}{$clusterid}++;

    # If there are more jobs for this queue, and the next job in the queue isn't
    # prelocked, lock some more
    $self->prelockSomeUsers
        if exists $self->{jobs}{$clusterid}
        && !$self->{jobs}{$clusterid}[0]->isPrelocked;

    return $job;
}

### METHOD: unassignJobForClient( $fdno )
### Unassign the job currently assigned to the client associated with the given
### I<fdno>.
sub unassignJobForClient {
    my JobServer $self = shift;
    my $fdno           = shift or confess "No client fdno";
    my $requeue        = shift || '';

    my ( $job, $src, );

    # If there is a currently assigned job, we have work to do
    if ( ( $job = delete $self->{assignments}{$fdno} ) ) {
        $src = $job->srcclusterid;

        # If the worker asked to finish it, assume it was completed and
        # timedbuffer it for statistics.
        if ( $job->isFinished ) {
            $self->{recentmoves}->add($job);
        }

        # Otherwise, requeue it if that's enabled
        else {

            if ($requeue) {
                $self->logMsg( 'info', "Re-adding job %s to queue", $job->stringify );
                $self->{jobs}{ $job->srcclusterid } ||= [];
                unshift @{ $self->{jobs}{ $job->srcclusterid } }, $job;
            }

            # Free up a slot on the source
            $self->debugMsg( 3, "Client %d dropped job %s", $fdno, $job->stringify );
        }

        # Delete the user's job and decrement the job count for the cluster the
        # job belonged to
        delete $self->{users}{ $job->userid };
        $self->{jobcounts}{$src}--;
        $self->debugMsg( 3, "Cluster %d now has %d clients", $src, $self->{jobcounts}{$src} );
    }

    return $job;
}

### METHOD: getJobForUser( $userid )
### Return the job associated with a given userid.
sub getJobForUser {
    my JobServer $self = shift;
    my $userid = shift or confess "No userid specified";

    return $self->{users}{$userid};
}

### METHOD: stopAllJobs( $client=JobServer::Client )
### Stop all pending and currently-assigned jobs.
sub stopAllJobs {
    my JobServer $self = shift;
    my $client = shift or confess "No client object";

    $self->stopNewJobs($client);
    $self->logMsg( 'notice', "Clearing currently-assigned jobs." );
    %{ $self->{assignments} } = ();
    %{ $self->{jobs} }        = ();
    %{ $self->{jobcounts} }   = ();
    %{ $self->{users} }       = ();

    return "Cleared all jobs.";
}

### METHOD: stopNewJobs( $client=JobServer::Client )
### Stop assigning pending jobs.
sub stopNewJobs {
    my JobServer $self = shift;
    my $client = shift or confess "No client object";

    $self->logMsg( 'notice', "Clearing pending jobs." );
    %{ $self->{jobs} } = ();
    foreach my $userid ( keys %{ $self->{users} } ) {
        delete $self->{users}{$userid} unless $self->{users}{$userid}->isFetched;
    }

    return "Cleared pending jobs.";
}

### METHOD: requestJobFinish( $client=JobServer::Client, $userid, $srcclusterid, $dstclusterid )
### Request authorization to finish a given job.
sub requestJobFinish {
    my JobServer $self = shift;
    my ( $client, $userid, $srcclusterid, $dstclusterid ) = @_;

    my (
        $fdno,    # The client's fdno
        $job,     # The client's currently assigned job
    );

    # Fetch the fdno of the client and try to get the job object they were last
    # assigned. If it doesn't exist, all jobs are stopped or something else has
    # happened, so advise the client to abort.
    $fdno = $client->fdno;
    if ( !exists $self->{assignments}{$fdno} ) {
        $self->logMsg( 'warn', "Client $fdno: finish on unassigned job" );
        return undef;
    }

    # If the job the client was last assigned doesn't match the userid they've
    # specified, abort.
    $job = $self->{assignments}{$fdno};
    if ( $job->userid != $userid ) {
        $self->logMsg( 'warn', "Client %d: finish for non-assigned job %s",
            $fdno, $job->stringify );
        return undef;
    }

    # Otherwise mark the job as finished and advise the client that they can
    # proceed.
    $job->setFinishTime;
    $self->debugMsg( 2, 'Client %d finishing job %s', $fdno, $job->stringify );

    return "Go ahead with job " . $job->stringify;
}

### METHOD: getJobList( undef )
### Return a hashref of job stats. The hashref will contain three arrays: the
### 'queued_jobs' array contains a line describing how many jobs are queued for
### each source cluster, the 'assigned_jobs' array contains a line per client
### that's currently moving a user, and the 'footer' array contains some lines
### of overall statistics about the server.
sub getJobList {
    my JobServer $self = shift;

    my (
        %stats,            # The returned job stats
        $queuedCount,      # Number of queued jobs
        $assignedCount,    # Number of jobs currently assigned
        $job,              # Job object iterator
        $rates,            # Rate-limit table
    );

    %stats = ( queued_jobs => [], assigned_jobs => [], footer => [] );
    $queuedCount = $assignedCount = 0;
    $rates       = $self->getClusterRateLimits;

    # The first sublist: queued jobs
    foreach my $clusterid ( sort keys %{ $self->{jobs} } ) {
        push @{ $stats{queued_jobs} },
            sprintf(
            "%3d: %5d jobs queued @ limit %d",
            $clusterid, scalar @{ $self->{jobs}{$clusterid} },
            $rates->{$clusterid}
            );
        $queuedCount += scalar @{ $self->{jobs}{$clusterid} };
    }

    # Second sublist: assigned jobs
    foreach my $fdno ( sort keys %{ $self->{assignments} } ) {
        $job = $self->{assignments}{$fdno};
        push @{ $stats{assigned_jobs} },
            sprintf( "%3d: working on moving %7d from %3d to %3d",
            $fdno, $job->userid, $job->srcclusterid, $job->dstclusterid );
        $assignedCount++;
    }

    # Append the footer lines
    push @{ $stats{footer} },
        sprintf( "  %d queued jobs, %d assigned jobs for %d clusters",
        $queuedCount, $assignedCount, scalar keys %{ $self->{jobs} } );

    if ( $self->{totaljobs} ) {
        push @{ $stats{footer} },
            sprintf(
            "  %d of %d total jobs assigned since %s (%0.1f/s)",
            $self->{totaljobs} - $queuedCount,
            $self->{totaljobs},
            scalar localtime( $self->{starttime} ),
            ( time - $self->{starttime} ) / ( $self->{totaljobs} )
            );
    }
    else {
        push @{ $stats{footer} },
            sprintf( "  No jobs assigned since startup (%s)",
            scalar localtime( $self->{starttime} ) );
    }

    return \%stats;
}

### METHOD: getSourceCount( undef )
### Return a hash (or hashref in scalar context) of srcclusterids => # of
### pending (queued) jobs.
sub getJobCounts {
    my JobServer $self = shift;
    my %rhash = map { $_ => scalar @{ $self->{jobs}{$_} } } keys %{ $self->{jobs} };

    return wantarray ? %rhash : \%rhash;
}

### METHOD: shutdown( $agent )
### Shut the server down.
sub shutdown {
    my JobServer $self = shift;
    my $agent = shift;

    # Stop incoming connections (:TODO: remove it from Danga::Socket?)
    $self->{listener}->close;

    # Clear jobs so no more get handed out while clients are closing
    $self->{jobs}  = {};
    $self->{users} = {};
    $self->logMsg( 'notice', "Server shutdown by %s", $agent->stringify );

    # Drop all clients
    foreach my $client ( values %{ $self->{clients} } ) {
        $client->write("Server shutdown.\r\n");
        $client->close;
    }

    exit;
}

#####################################################################
### E V E N T   S U B S Y S T E M   M E T H O D S
#####################################################################

### METHOD: handleEvent( $type, @args )
### Handle an event of the given I<type> with the specified I<args>.
sub handleEvent {
    my JobServer $self = shift;
    my ( $type, @args ) = @_;

    # Invoke each registered handler for the given type
    for my $func ( values %{ $self->{handlers}{$type} } ) {
        $func->(@args);
    }
}

### METHOD: handlers( [$type] )
### Return a hash of all registered handlers of the given I<type>, or all
### handlers keyed by type if no type is specified.
sub handlers {
    my JobServer $self = shift;
    my $type = shift || '';

    my $rhash;

    if ($type) {
        $rhash = $self->{handlers}{$type};
    }
    else {
        $rhash = $self->{handlers};
    }

    return () unless $rhash;
    return wantarray ? %$rhash : $rhash;
}

### METHOD: addHandlerToAll( $key, \&code )
### Add the specified callback (I<code>) as an event handler for all implemented
### event types. The associated I<key> can be used to later remove the
### handler/s. Returns the number of event types subscribed to.
sub addHandlerToAll {
    my JobServer $self = shift;
    my ( $key, $code ) = @_;

    my $count = 0;
    foreach my $type ( keys %{ $self->{handlers} } ) {
        $count++ if $self->addHandler( $type, $key, $code );
    }

    return $count;
}

### METHOD: removeHandlerFromAll( $key )
### Remove all event callbacks for the specified I<key>. Returns the number of
### handlers removed.
sub removeHandlerFromAll {
    my JobServer $self = shift;
    my $key = shift;

    my $count = 0;
    foreach my $type ( keys %{ $self->{handlers} } ) {
        $count++ if $self->removeHandler( $type, $key );
    }

    return $count;
}

### METHOD: addHandler( $type, $key, \&code )
### Add a callback (I<code>) that handles events of the given I<type>. The
### I<key> argument can be used to later remove the handler.
sub addHandler {
    my JobServer $self = shift;
    my ( $type, $key, $code ) = @_;

    confess "No such event type '$type'"
        unless exists $self->{handlers}{$type};
    confess "$type handler for '$key' is a ",
        ( ref $code ? "simple scalar '$code'" : ref $code ), ", not a CODE ref."
        unless ref $code eq 'CODE';

    $self->{handlers}{$type}{$key} = $code;
}

### METHOD: removeHandler( $type, $key )
### Remove and return the callback associated with the specified I<key> and
### event I<type>.
sub removeHandler {
    my JobServer $self = shift;
    my ( $type, $key ) = @_;

    no warnings 'uninitialized';
    return delete $self->{handlers}{$type}{$key};
}

### METHOD: subscribe( $client=JobServer::Client, $type, $args )
### Subscribe the given I<client> to the given I<type> of server events with the
### given I<args>.
sub subscribe {
    my JobServer $self = shift;
    my ( $client, $type, $args ) = @_;

    my $method = sprintf( 'subscribe%sEvents', ucfirst $type );
    my $func   = $self->can($method)
        or die "No such event type '$type' (No $method method)";
    $self->debugMsg( 2, "Subscribing client %d to %s events via %s(%s)",
        $client->fdno, $type, $method, $args );

    return $func->( $self, $client, $args );
}

### METHOD: unsubscribe( $client=JobServer::Client, $type, $args )
### Unsubscribe the given I<client> to the given I<type> of server events with the
### given I<args>.
sub unsubscribe {
    my JobServer $self = shift;
    my ( $client, $type ) = @_;

    my $method = sprintf( 'unsubscribe%sEvents', ucfirst $type );
    my $func   = $self->can($method)
        or die "No such event type '$type' (No $method method)";

    return $func->( $self, $client );
}

### METHOD: subscribeLogEvents( $client, $level )
### Register a log event handler for the specified I<client> at the given
### I<level>, replacing any currently-extant one.
sub subscribeLogEvents {
    my JobServer $self = shift;
    my ( $client, $level ) = @_;
    my $ll = $LogLevels{$level};

    my $callback = sub {
        my ( $loglevel, $msg ) = @_;
        return () unless $LogLevels{$loglevel} >= $ll;
        $client->eventMessage( 'log', "[$loglevel] $msg" );
    };

    $self->addHandler( 'log', $client->fdno, $callback );

    return "Subscribed to log events for level '$level'";
}

### METHOD: unsubscribeLogEvents( $client )
### Unregister the log handler registered for the given I<client>.
sub unsubscribeLogEvents {
    my JobServer $self = shift;
    my $client = shift or croak "No client";

    $self->removeHandler( 'log', $client->fdno );
    return "Unsubscribed from log events.";
}

### METHOD: subscribeDebugEvents( $client, $level )
### Register a debug event handler for the specified I<client> at the given
### I<level>, replacing any currently-extant one.
sub subscribeDebugEvents {
    my JobServer $self = shift;
    my ( $client, $level ) = @_;

    my $callback = sub {
        my ( $debuglevel, $msg ) = @_;
        return () unless $debuglevel <= $level;
        $client->eventMessage( 'debug', "[$debuglevel] $msg" );
    };

    $self->addHandler( 'debug', $client->fdno, $callback );

    return "Subscribed to debug events for level '$level'";
}

### METHOD: unsubscribeDebugEvents( $client )
### Unregister the debug handler registered for the given I<client>.
sub unsubscribeDebugEvents {
    my JobServer $self = shift;
    my $client = shift or croak "No client";

    $self->removeHandler( 'debug', $client->fdno );
    return "Unsubscribed from debug events.";
}

### METHOD: subscribeAddEvents( $client, $level )
### Register an 'add' event handler for the specified I<client>.
sub subscribeAddEvents {
    my JobServer $self = shift;
    my $client = shift or croak "No client";

    my $callback = sub {
        my $count = shift;
        $client->eventMessage( 'add', "$count jobs added" );
    };

    $self->addHandler( 'add', $client->fdno, $callback );

    return "Subscribed to add events";
}

### METHOD: unsubscribeAddEvents( $client )
### Unregister the 'add' handler registered for the given I<client>.
sub unsubscribeAddEvents {
    my JobServer $self = shift;
    my $client = shift or croak "No client";

    $self->removeHandler( 'add', $client->fdno );
    return "Unsubscribed from add events.";
}

#####################################################################
### ' P R O T E C T E D '   M E T H O D S
#####################################################################

### METHOD: daemonize( undef )
### Double fork and become a good little daemon
sub daemonize {
    my JobServer $self = shift;

    $self->stubbornFork(5) && exit 0;

    # Become session leader to detach from controlling tty
    POSIX::setsid() or croak "Couldn't become session leader: $!";

    # Fork again, ignore hangup to avoid reacquiring a controlling tty
    {
        local $SIG{HUP} = 'IGNORE';
        $self->stubbornFork(5) && exit 0;
    }

    # Change working dir to the filesystem root, clear the umask
    chdir "/";
    umask 0;

    # Close standard file descriptors and reopen them to /dev/null
    close STDIN  && open STDIN,  "/dev/null";
    close STDOUT && open STDOUT, ">/dev/null";
    close STDERR && open STDERR, "+>&STDOUT";
}

### METHOD: stubbornFork( $maxTries )
### Attempt to fork through errors
sub stubbornFork {
    my JobServer $self = shift;
    my $maxTries = shift || 5;

    my ( $pid, $tries, );

    $tries = 0;
FORK: while ( $tries <= $maxTries ) {
        if ( ( $pid = fork ) ) {
            return $pid;
        }
        elsif ( defined $pid ) {
            return 0;
        }
        elsif ( $! =~ m{no more process} ) {
            sleep 5;
            next FORK;
        }
        else {
            die "Cannot fork: $!";
        }
    }
    continue {
        $tries++;
    }

    die "Failed to fork after $tries tries: $!";
}

### METHOD: debugLevel( [$newLevel] )
### Get/set the server's debugging level.
sub debugLevel {
    my JobServer $self = shift;

    $self->{config}{debugLevel} = ( shift || 0 ) if @_;
    return $self->{config}{debugLevel};
}

### METHOD: debugMsg( $level, $format, @args )
### If the debug level is C<$level> or above, and there are debug handlers
### defined, call each of them at the specified level with the given printf
### C<$format> and C<@args>.
sub debugMsg {
    my JobServer $self = shift;
    my $level          = shift;
    my $debugLevel     = $self->{config}{debugLevel};
    return unless $level && $debugLevel >= abs $level;
    return unless %{ $self->{handlers}{debug} };

    my $msg = shift;
    $msg =~ s{[\r\n]+$}{};

    if ( $debugLevel > 1 ) {
        my $caller = caller;
        $msg = "<$caller> $msg";
    }

    # Call each subscribed debug event handler with the level and message.
    $msg = $self->formatLogMsg( $msg, @_ );
    $self->handleEvent( 'debug', $level, $msg );
}

### METHOD: logMsg( $level, $format, @args )
### Call any log handlers that have been defined at the specified level with the
### given printf C<$format> and C<@args>.
sub logMsg {
    my JobServer $self = shift;
    return () unless %{ $self->{handlers}{log} };
    my $level = shift or return ();
    my $msg   = $self->formatLogMsg(@_);

    $self->handleEvent( 'log', $level, $msg );
}

### METHOD: formatLogMsg( $format, @args )
### Create and return a message for the given C<sprintf()>-style I<format> and
### I<args>, dumping any complex datatypes and marking the undefined value.
sub formatLogMsg {
    my JobServer $self = shift;
    my $format = shift;

    # Fetch level and format and strip returns off the latter.
    $format =~ s{[\r\n]+$}{};

    # Turn any references or undefined values in the arglist into dumped strings
    my @args =
        map { defined $_ ? ( ref $_ ? Data::Dumper->Dumpxs( [$_], [ ref $_ ] ) : $_ ) : '(undef)' }
        @_;
    return sprintf( $format, @args );
}

#####################################################################
### J O B   C L A S S
#####################################################################
package JobServer::Job;
use strict;

BEGIN {
    use Carp qw{croak confess};
    use Time::HiRes qw{time};
    use Scalar::Util qw{blessed};

    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
    use LJ::Config;
    LJ::Config->load;

    use fields (
        'server',          # The server this job belongs to
        'userid',          # The userid of the user to move
        'srcclusterid',    # The cluster id of the source cluster
        'dstclusterid',    # Cluster id of the destination cluster
        'createtime',      # Epoch time of job creation
        'prelocktime',     # Epoch time of prelock, 0 if not prelocked
        'fetchtime',       # Time the job was given to a mover, 0 if unassigned
        'finishtime',      # Epoch time of server finish authorization
        'options',         # Job options passed between populator and mover
    );
}

### Class globals
our ($ReadOnlyCapBit);

INIT {
    # Find the readonly cap class, complain if not found
    $ReadOnlyCapBit = undef;

    # Find the moveinprogress bit from the caps hash
    foreach my $bit ( keys %LJ::CAP ) {
        next unless exists $LJ::CAP{$bit}{_name};
        if (   $LJ::CAP{$bit}{_name} eq '_moveinprogress'
            && $LJ::CAP{$bit}{readonly} == 1 )
        {
            $ReadOnlyCapBit = $bit;
            last;
        }
    }

    die "Cannot mark user readonly without a ReadOnlyCapBit. Check %LJ::CAP"
        unless $ReadOnlyCapBit;

}

### (CONSTRUCTOR) METHOD: new( [$userid, $srcclusterid, $dstclusterid )
### Create and return a new JobServer::Job object.
sub new {
    my JobServer::Job $self = shift;
    my $server = shift or confess "no server object";
    croak "Illegal first argument: expected a JobServer::Client, got a ",
        ref $server ? ref $server : "simple scalar ('$server')"
        unless blessed $server && $server->isa('JobServer::Client');

    $self = fields::new($self) unless ref $self;

    # Split instance vars from a string with a colon in the second or later
    # position
    if ( index( $_[0], ':' ) > 0 ) {
        my ( $idtuple, $options ) = split /\s+/, $_[0], 2;

        # Split '<uid>:<scid>:<dcid>' into members
        @{$self}{qw{userid srcclusterid dstclusterid}} = split /:/, $idtuple, 3;

        # Split '<k>=<v> <k2>=<v2>' into a hashref
        if ($options) {
            $self->{options} = { map { split /=/, $_, 2 } split( /\s+/, $options ) };
        }
        else {
            $self->{options} = {};
        }
    }

    # Allow list arguments as well
    else {
        # First 3 args are id members
        @{$self}{qw{userid srcclusterid dstclusterid}} =
            splice( @_, 0, 3 );

        # Any remaining are assumed to be pairs in an options hash
        $self->{options} = {@_};
    }

    # Check for the stuff we need
    croak "Invalid job specifications: No userid"
        unless defined $self->{userid};
    croak "Invalid job specifications: No source clusterid"
        unless defined $self->{srcclusterid};
    croak "Invalid job specifications: No destination clusterid"
        unless defined $self->{dstclusterid};

    $self->{server}      = $server;
    $self->{createtime}  = time;
    $self->{prelocktime} = 0.0;
    $self->{fetchtime}   = 0.0;
    $self->{finishtime}  = 0.0;

    return $self;
}

### METHOD: userid( [$newuserid] )
### Get/set the job's userid.
sub userid {
    my JobServer::Job $self = shift;
    $self->{userid} = shift if @_;
    return $self->{userid};
}

### METHOD: srcclusterid( [$newsrcclusterid] )
### Get/set the job's srcclusterid.
sub srcclusterid {
    my JobServer::Job $self = shift;
    $self->{srcclusterid} = shift if @_;
    return $self->{srcclusterid};
}

### METHOD: dstclusterid( [$newdstclusterid] )
### Get/set the job's dstclusterid.
sub dstclusterid {
    my JobServer::Job $self = shift;
    $self->{dstclusterid} = shift if @_;
    return $self->{dstclusterid};
}

### METHOD: stringify( undef )
### Return a scalar containing the stringified representation of the job.
sub stringify {
    my JobServer::Job $self = shift;
    return sprintf(
        '%d:%d:%d %0.1f %s',
        @{$self}{ 'userid', 'srcclusterid', 'dstclusterid' },
        $self->secondsSinceLock, $self->optString
    );
}

### METHOD: prettyString( undef )
### Return a less-parseable, but more-readable string representation of the job
### than C<stringify()> provides.
sub prettyString {
    my JobServer::Job $self = shift;

    return sprintf( "User %d %s from %d to %d (%s):\n\t%s",
        $self->{userid}, $self->verb, $self->{srcclusterid}, $self->{dstclusterid},
        $self->optString, $self->timeString, );
}

### METHOD: verb( undef )
### Return the correct conjugation of the verb "to move" that would describe the
### job given its current state.
sub verb {
    my JobServer::Job $self = shift;

    return "moved"  if $self->{finishtime};
    return "moving" if $self->{fetchtime};
    return "to move";
}

### METHOD: optString( undef )
### Return the job's options as a string.
sub optString {
    my JobServer::Job $self = shift;
    my $opts = $self->{options};
    return join( " ", map { "$_=$opts->{$_}" } keys %$opts );
}

### METHOD: timeString( undef )
### Return the job's various timestamps (if set).
sub timeString {
    my JobServer::Job $self = shift;
    my @parts = ();

    push @parts, sprintf( '%0.2fs old',    $self->age );
    push @parts, sprintf( 'locked %0.2fs', $self->secondsSinceLock )
        if $self->{prelocktime};
    push @parts,
        sprintf( 'fetched %0.2fs ago (%0.1fs queued)',
        $self->secondsSinceFetch, $self->{fetchtime} - $self->{createtime} )
        if $self->{fetchtime};
    push @parts, sprintf( 'finished in %0.2fs', $self->aliveTime )
        if $self->{finishtime};

    return join ", ", @parts;
}

### METHOD: prelock( undef )
### Mark the user in this job read-only and set the prelocktime.
sub prelock {
    my JobServer::Job $self = shift;

    my $dbh = LJ::get_db_writer()
        or return 0;

    # both before and after updating a user's read-only flag we add the
    # user to the 'readonly_user' table, which is just an index onto
    # users who /might/ be in read-only.  another cronjob can periodically
    # clean those and make sure nobody is stranded in readonly, without
    # resorting to a full tablescan of the user table.
    $dbh->do( "INSERT IGNORE INTO readonly_user SET userid=?", undef, $self->{userid} );
    my $rval = LJ::update_user( $self->{userid}, { raw => "caps = caps | (1<<$ReadOnlyCapBit)" } );

    if ($rval) {
        $dbh->do( "INSERT IGNORE INTO readonly_user SET userid=?", undef, $self->{userid} );
        $self->setPrelocktime;
        $self->{options}{prelocked} = 1;
        $self->{server}->debugMsg( 4, q{Prelocked user %d}, $self->{userid} );
    }
    else {
        $self->{server}
            ->logMsg( 'warn', q{Couldn't prelock user %d: %s}, $self->{userid}, $DBI::errstr );
    }

    return $self->{prelocktime};
}

### METHOD: prelocktime( [$newprelocktime] )
### Get the floating-point epoch time when the user record corresponding to the
### job's C<userid> was set read-only.
sub prelocktime {
    my JobServer::Job $self = shift;
    return $self->{prelocktime};
}

### METHOD: setPrelocktime( undef )
### Set the prelocktime to the current floating-point epoch time.
sub setPrelocktime {
    my JobServer::Job $self = shift;
    return $self->{prelocktime} = time;
}

### METHOD: secondsSinceLock( undef )
### Return the number of seconds since the job's user was prelocked, or 0 if the
### user isn't prelocked.
sub secondsSinceLock {
    my JobServer::Job $self = shift;
    return 0.0 unless $self->{prelocktime};
    return time - $self->{prelocktime};
}

### METHOD: isPrelocked( undef )
### Returns a true value if the user corresponding to the job has already been
### marked read-only.
sub isPrelocked {
    my JobServer::Job $self = shift;
    return $self->{prelocktime} != 0;
}

### METHOD: finishTime( [$newtime] )
### Returns the floating-point epoch time when the job was 'finished'.
sub finishTime {
    my JobServer::Job $self = shift;
    return $self->{finishtime};
}

### METHOD: setFinishTime( undef )
### Set the finishtime to the current floating-point epoch time.
sub setFinishTime {
    my JobServer::Job $self = shift;
    return $self->{finishtime} = time;
}

### METHOD: secondsSinceFinish( undef )
### Returns the number of seconds that have elapsed since the job was
### 'finished'.
sub secondsSinceFinish {
    my JobServer::Job $self = shift;
    return 0 unless $self->{finishtime};
    return time - $self->{finishtime};
}

### METHOD: isFinished( undef )
### Returns a true value if the mover has requested authorization from the
### jobserver to finish the job.
sub isFinished {
    my JobServer::Job $self = shift;
    return $self->{finishtime} != 0;
}

### METHOD: fetchtime( undef )
### Get the floatin-point epoch time when the job was fetched by a mover.
sub fetchtime {
    my JobServer::Job $self = shift;
    return $self->{fetchtime};
}

### METHOD: setFetchtime( undef )
### Set the fetchtime to the current floating-point epoch time.
sub setFetchtime {
    my JobServer::Job $self = shift;
    return $self->{fetchtime} = time;
}

### METHOD: secondsSinceFetch( undef )
### Return the number of seconds since the job was fetched by a mover.
sub secondsSinceFetch {
    my JobServer::Job $self = shift;
    return 0 unless $self->{fetchtime};
    return time - $self->{fetchtime};
}

### METHOD: isFetched( undef )
### Returns a true value if the job has been assigned to a mover.
sub isFetched {
    my JobServer::Job $self = shift;
    return $self->{fetchtime} != 0;
}

### METHOD: createTime( undef )
### Return the floating-point epoch time when the job was created.
sub createTime {
    my JobServer::Job $self = shift;
    return $self->{createtime};
}

### METHOD: age( undef )
### Return the number of floating-point seconds since the job was created.
sub age {
    my JobServer::Job $self = shift;
    return time - $self->{createtime};
}

### METHOD: aliveTime( undef )
### Return the number of floating-point seconds the job was alive, which is the
### time between when it was created and when it was finished.
sub aliveTime {
    my JobServer::Job $self = shift;
    return 0 unless $self->{finishtime};
    return $self->{finishtime} - $self->{createtime};
}

### METHOD: activeTime( undef )
### Return the number of floating-point seconds the job was active, which is the
### time between when it was fetched and when it was finished.
sub activeTime {
    my JobServer::Job $self = shift;
    return 0 unless $self->{finishtime} && $self->{fetchtime};
    return $self->{finishtime} - $self->{fetchtime};
}

### METHOD: debugMsg( $level, $format, @args )
### Send a debugging message to the server this job belongs to.
sub debugMsg {
    my JobServer::Job $self = shift;
    $self->{server}->debugMsg(@_);
}

### METHOD: logMsg( $type, $format, @args )
### Send a log message to the server this job belongs to.
sub logMsg {
    my JobServer::Job $self = shift;
    $self->{server}->logMsg(@_);
}

#####################################################################
### C L I E N T   B A S E   C L A S S
#####################################################################
package JobServer::Client;

# Props to Junior for lots of this code, stolen largely from the SPUD server.

BEGIN {
    use Carp qw{croak confess};
    use base qw{Danga::Socket};
    use fields qw{read_buf server state};
}

our ( $Tuple, $JobOption, $JobSpec, %CommandTable, $CommandPattern );

INIT {

    # Pattern for matching job id tuples of the form:
    #   <userid>:<srcclusterid>:<dstclusterid>
    $Tuple = qr{\d+:\d+:\d+};

    # Pattern for matching one job-spec option which is a moveucluster option
    # key-value pair in the form:
    #   <optioname>=<optval>
    $JobOption = qr{\s+\w+=\w+};

    # Pattern for matching a whole job-spec
    $JobSpec = qr{$Tuple$JobOption*};

    # Commands the server understands. Each entry should be paired with a method
    # called cmd_<command_name>. The 'args' element contains a regexp for
    # matching the command's arguments after whitespace-stripping on both sides;
    # any capture-groups will be passed to the method as arguments. Commands
    # which don't match the argument pattern will produce an error
    # message. E.g., if the pattern for 'foo_bar' is /^(\w+)\s+(\d+)$/, then
    # entering the command "foo_bar frobnitz 4" would call:
    #   ->cmd_foo_bar( "frobnitz", "4" )
    #
    # The 'help' element of each command is used to provide the information
    # necessary for the 'help' command.
    #
    # If an entry contains a 'form' element, it will be used to describe the
    # arguments which are expected/required by the command, and is used in the
    # 'form' part of the individual help for that command. If it is omitted, the
    # command is assumed by the help system to be standalone and take no arguments.
    %CommandTable = (

        # :TODO: Implement a 'desc' or 'longhelp' or something to augment the
        # per-command help.

        get_job => {
            help => "get a job (from mover)",
            args => qr{^$},
        },

        add_jobs => {
            help => "add one or more new jobs",
            form => "<userid>:<srcclusterid>:<dstclusterid> <options>[, ...]",
            args => qr{^((?:$JobSpec\s*,\s*)*$JobSpec)$},
        },

        source_counts => {
            help => "dump pending jobs per source cluster",
            args => qr{^$},
        },

        stop_moves => {
            help => "stop all moves",
            form => "[all]",
            args => qr{^(all)?$},
        },

        is_moving => {
            help => "check to see if a user is being moved",
            form => "<userid>",
            args => qr{^(\d+)$},
        },

        list_jobs => {
            help => "list internal state",
            args => qr{^$},
        },

        move_stats => {
            help => "List recent move statistics",
            args => qr{^$},
        },

        recent_moves => {
            help => "Show a log of recent moves",
            args => qr{^$},
        },

        set_rate => {
            help => "Set the rate for a given source cluster or for all clusters",
            form => "<globalrate> or <srcclusterid>:<rate>",
            args => qr{^(\d+)(?:[:\s]+(\d+))?\s*$},
        },

        show_rates => {
            help => "Show the rate settings for all clusters",
            args => qr{^$},
        },

        reset_rate => {
            help => "Clear rate settings for all or the given source cluster/s.",
            form => "[<srcclusterid>]",
            args => qr{^(\d+)?$},
        },

        finish => {
            help => "request authorization to complete a move job",
            form => "<userid>:<srcclusterid>:<dstclusterid>",
            args => qr{^($Tuple)$},
        },

        quit => {
            help => "disconnect from the server",
            args => qr{^$},
        },

        shutdown => {
            help => "shut the server down",
            args => qr{^$},
        },

        lock => {
            help => "Pre-lock a given user's job. The job must have already been added.",
            form => '<userid>',
            args => qr{^(\d+)$},
        },

        clients => {
            help => "Show a list of connected clients",
            args => qr{^$},
        },

        subscribe => {
            help => "Subscribe to server events",
            form => '<type> <args>',
            args => qr{^(\w+)(?:\s+(.*))?$}i,
        },

        unsubscribe => {
            help => "Unsubscribe from server events",
            form => '<type>',
            args => qr{^(\w+)$},
        },

        handlers => {
            help => "List the event handlers registered with the server.",
            form => '[<type>]',
            args => qr{^(\w+)?$},
        },

        debuglevel => {
            help => "Get/set the debugging level of the server.",
            form => '[<level>]',
            args => qr{^([0-5])?$},
        },

        help => {
            help => "show list of commands or help for a particular command, if given.",
            form => "[<command>]",
            args => qr{^(\w+)?$},
        },

        ### Internal/debugging commands
        timedbuffer => { args => qr{^$} },

    );

    # Pattern to match command words
    $CommandPattern = join '|', keys %CommandTable;
    $CommandPattern = qr{^($CommandPattern)$};
}

### (CONSTRUCTOR) METHOD: new( $server=JobServer, $socket=IO::Socket )
### Create a new JobServer::Client object for the given I<socket> and I<server>.
sub new {
    my JobServer::Client $self = shift;
    my $server = shift or confess "no server argument";
    my $sock   = shift or confess "no socket argument";

    $self = fields::new($self) unless ref $self;
    $self->SUPER::new($sock);

    $self->{server} = $server;
    $self->{state}  = 'new';

    return $self;
}

### METHOD: state( [$newstate] )
### Get/set the client's state message.
sub state {
    my JobServer::Client $self = shift;

    $self->{state} = shift if @_;
    return $self->{state};
}

### METHOD: stringify( undef )
### Return a string representation of the client object.
sub stringify {
    my JobServer::Client $self = shift;

    return sprintf( '%s:%d', $self->{sock}->peerhost, $self->{sock}->peerport );
}

### METHOD: event_read( undef )
### Readable event callback -- read input from the client and append it to the
### read buffer. Then peel lines off the read buffer and send them to the line
### processor.
sub event_read {
    my JobServer::Client $self = shift;

    my $bref = $self->read(1024);

    if ( !defined $bref ) {
        $self->close;
        return undef;
    }

    $self->{read_buf} .= $$bref;

    while ( $self->{read_buf} =~ s/^(.+?)\r?\n// ) {
        $self->processLine($1);
    }

}

### METHOD: close( undef )
### Close the client connection after unregistering from the server --
### overridden from Danga::Socket.
sub close {
    my JobServer::Client $self = shift;

    $self->{server}->disconnectClient($self) if $self->{server};
    $self->SUPER::close;
}

### METHOD: sock( undef )
### Return the IO::Socket object that corresponds to this client.
sub sock {
    my JobServer::Client $self = shift;
    return $self->{sock};
}

### METHOD: sock( undef )
### Return the file descriptor that is associated with the IO::Socket object
### that corresponds to this client.
sub fdno {
    my JobServer::Client $self = shift;
    return fileno( $self->{sock} );
}

### METHOD: event_err( undef )
### Handle Danga::Socket error events.
sub event_err {
    my JobServer::Client $self = shift;
    $self->close;
}

### METHOD: event_hup( undef )
### Handle Danga::Socket hangup events.
sub event_hup {
    my JobServer::Client $self = shift;
    $self->close;
}

### METHOD: debugMsg( $level, $format, @args )
### Send a debugging message to the server.
sub debugMsg {
    my JobServer::Client $self = shift;
    $self->{server}->debugMsg(@_);
}

### METHOD: logMsg( $type, $format, @args )
### Send a log message to the server.
sub logMsg {
    my JobServer::Client $self = shift;
    $self->{server}->logMsg(@_);
}

### METHOD: processLine( $line )
### Command dispatcher -- parse I<line> as a command and dispatch it to the
### correct command handler method. The class-global %CommandTable contains the
### dispatch table for this method.
sub processLine {
    my JobServer::Client $self = shift;
    my $line = shift or return undef;

    my (
        $cmd,        # Command word
        $args,       # Argument string from user
        $cmdinfo,    # Command hashref
        @args,       # Parsed arguments
        $method,     # Command method to call
    );

    # Split the line into command and argument string
    ( $cmd, $args ) = split /\s+/, $line, 2;
    $args = '' if !defined $args;

    $self->debugMsg( 5, "Matching '%s' against command table pattern %s", $cmd, $CommandPattern );

    # If it's a command in the command table, dispatch to the appropriate
    # command handler after parsing any arguments.
    if ( $cmd =~ $CommandPattern ) {
        $method  = "cmd_$1";
        $cmdinfo = $CommandTable{$1};

        # Parse command arguments
        if ( @args = ( $args =~ $cmdinfo->{args} ) ) {

            # If the pattern didn't contain captures, throw away the args
            @args = () unless ( @+ > 1 );

            eval { $self->$method(@args) };
            if ($@) { $self->errorResponse($@) }
        }

        # Valid command, but bad args
        else {
            $self->errorResponse( "Usage: $cmd " . $cmdinfo->{form} );
        }
    }

    # Invalid command
    else {
        $self->errorResponse("Invalid command '$cmd'");
    }

    return 1;
}

### METHOD: okayResponse( @msg )
### Set an 'OK' response string made up of the I<msg> parts concatenated
### together.
sub okayResponse {
    my JobServer::Client $self = shift;
    my $msg = join( '', @_ );

    1 while chomp($msg);

    $self->debugMsg(
        3,
        "[Client %s:%d] OK: %s",
        $self->{sock}->peerhost,
        $self->{sock}->peerport, $msg,
    );

    $self->write("OK $msg\r\n");
}

### METHOD: errorResponse( @msg )
### Send an 'ERR' response string made up of the I<msg> parts concatenated
### together.
sub errorResponse {
    my JobServer::Client $self = shift;
    my $msg = join( '', @_ );

    # Trim newlines off the end of the message
    1 while chomp($msg);

    $self->logMsg(
        "error",
        "[Client %s:%d] ERR: %s",
        $self->{sock}->peerhost,
        $self->{sock}->peerport, $msg,
    );

    $msg =~ s{at \S+ line \d+\..*}{};
    $self->write("ERR $msg\r\n");
}

### METHOD: multilineResponse( $msg, @lines )
### Send an 'OK' response containing the given I<msg> followed by one or more
### I<lines> of a multi-line response followed by an 'END'.
sub multilineResponse {
    my JobServer::Client $self = shift;
    my ( $msg, @lines ) = @_;

    chomp(@lines);
    $msg =~ s{:\s*$}{};

    $self->okayResponse("$msg:");
    $self->write( join( "\r\n", @lines, "END" ) . "\r\n" );
}

### METHOD: eventMessage( $type, $msg )
### Send an event notification I<msg> for the given I<type> to the client.
sub eventMessage {
    my JobServer::Client $self = shift;
    my ( $type, $msg ) = @_;

    1 while chomp( $type, $msg );
    $self->write("EVENT {$type} $msg\r\n");
}

### FUNCTION: stringifyHandlers( \%handlers )
### Stringify a hashref full of handler coderefs.
sub stringifyHandlers {
    my $handlers = shift or confess "No handlers argument";

    my @rows = ();

    foreach my $key ( keys %$handlers ) {
        if ( ref $handlers->{$key} eq 'HASH' ) {
            push( @rows,
                "  $key => {", map { "    $_" } stringifyHandlers( $handlers->{$key} ), "}" );
        }

        else {
            push @rows, sprintf( '%s -> %s', $key, $handlers->{$key} );
        }
    }

    return @rows;
}

#####################################################################
### C O M M A N D   M E T H O D S
#####################################################################

### METHOD: cmd_get_job( undef )
### Command handler for the C<get_job> command.
sub cmd_get_job {
    my JobServer::Client $self = shift;

    $self->{state} = 'getting job';
    my $job = $self->{server}->getJob($self);

    if ($job) {
        my $jobString = $job->stringify;
        $self->{state} = sprintf( 'got job %s', $jobString );
        return $self->okayResponse( "JOB " . $jobString );
    }
    else {
        $self->{state} = 'idle (no jobs)';
        return $self->okayResponse("IDLE");
    }
}

### METHOD: cmd_add_jobs( $argstring )
### Command handler for the C<add_job> command.
sub cmd_add_jobs {
    my JobServer::Client $self = shift;
    my $argstring = shift or return;

    # Turn the argument into an array of arrays
    my @tuples = map { JobServer::Job->new( $self, $_ ) } split /\s*,\s*/, $argstring;

    $self->{state} = sprintf 'adding %d jobs', scalar @tuples;
    my @responses = $self->{server}->addJobs(@tuples);
    $self->{state} = 'idle';

    return $self->multilineResponse( "Done", @responses );
}

### METHOD: cmd_source_counts( undef )
### Command handler for the C<source_counts> command.
sub cmd_source_counts {
    my JobServer::Client $self = shift;
    $self->{state} = 'source counts';

    my %counts = $self->{server}->getJobCounts;
    my @lines  = map { sprintf '%4d: %d', $_, $counts{$_} } sort keys %counts;

    return $self->multilineResponse( 'Source counts:', @lines );
}

### METHOD: cmd_stop_moves( undef )
### Command handler for the C<stop_moves> command.
sub cmd_stop_moves {
    my JobServer::Client $self = shift;
    my $allFlag = shift || '';

    $self->{state} = 'stop moves';
    my $msg;

    if ($allFlag) {
        $msg = $self->{server}->stopAllJobs($self);
    }
    else {
        $msg = $self->{server}->stopNewJobs($self);
    }

    $self->okayResponse($msg);
}

### METHOD: cmd_is_moving( undef )
### Command handler for the C<is_moving> command.
sub cmd_is_moving {
    my JobServer::Client $self = shift;
    my $userid = shift or croak "No userid";

    $self->{state} = 'is moving';
    $self->debugMsg( 2, "Checking to see if user %d is moving.", $userid );

    my $job = $self->{server}->getJobForUser($userid);
    my $msg;

    if ($job) {
        $self->debugMsg( 3, "is_moving: Got a job for userid $userid" );
        $msg = "1";
    }
    else {
        $self->debugMsg( 3, "is_moving: No job for userid $userid" );
        $msg = "0";
    }

    return $self->okayResponse($msg);
}

### METHOD: cmd_list_jobs( undef )
### Command handler for the C<list_jobs> command.
sub cmd_list_jobs {
    my JobServer::Client $self = shift;
    $self->{state} = 'list jobs';

    my $stats = $self->{server}->getJobList;

    return $self->multilineResponse(
        "Joblist:", "Queued Jobs", @{ $stats->{queued_jobs} },
        "",
        "Assigned Jobs",
        @{ $stats->{assigned_jobs} },
        "", @{ $stats->{footer} },
    );
}

### METHOD: cmd_move_stats( undef )
### Command handler for the C<move_stats> command.
sub cmd_move_stats {
    my JobServer::Client $self = shift;

    my (
        @jobs,      # Recently-finished job objects
        %times,     # Per-cluster/global time sums
        %counts,    # Per-cluster job counts
        $totaltime,
        $totalcount,
        @averages,    # Average 'alive' times
        @stats,       # Statistic lines
    );

    $self->{state} = 'move_stats';
    @jobs = $self->{server}->recentmoves
        or return $self->multilineResponse( "Move stats:", "No finished jobs" );

    $totaltime  = 0;
    $totalcount = 0;

    # Build average 'alive' times
    foreach my $job (@jobs) {
        $times{ $job->srcclusterid } += $job->aliveTime;
        $totaltime += $job->aliveTime;
        $counts{ $job->srcclusterid }++;
        $totalcount++;
    }

    # Generate averages
    @averages = map {
        sprintf( ' c%d: %d @ %0.2fs, %0.2fs avg.',
            $_, $counts{$_}, $times{$_}, $times{$_} / $counts{$_} )
    } sort keys %times;
    push @averages,
        sprintf( ' total: %d @ %0.2fs, %0.2fs avg.',
        $totalcount, $totaltime, $totaltime / $totalcount );

    # Return the statistics
    return $self->multilineResponse( "Move stats:", "Average 'alive' times (create->finish)",
        @averages, );
}

### METHOD: cmd_recent_moves( undef )
### Command handler for the C<recent_moves> command.
sub cmd_recent_moves {
    my JobServer::Client $self = shift;

    $self->{state} = 'recent_moves';

    my @jobs = $self->{server}->recentmoves;

    return $self->multilineResponse( "Recent moves", map { $_->prettyString } @jobs );
}

### METHOD: cmd_set_rate( undef )
### Command handler for the C<set_rate> command.
sub cmd_set_rate {
    my JobServer::Client $self = shift;
    my ( $clusterid, $rate ) = @_;

    my $msg;

    # Global rate
    if ( !defined $rate ) {
        $rate          = $clusterid;
        $self->{state} = "set global rate";
        $msg           = $self->{server}->setGlobalRateLimit($rate);
    }

    else {
        $self->{state} = "set rate for cluster $clusterid";
        $msg = $self->{server}->setClusterRateLimit( $clusterid, $rate );
    }

    return $self->okayResponse($msg);
}

### METHOD: cmd_show_rates( undef )
### Command handler for the C<show_rates> command.
sub cmd_show_rates {
    my JobServer::Client $self = shift;

    $self->{state} = 'show_rates';
    my %rules = $self->{server}->raterules;
    my @lines = map { sprintf '%6s: %2d', $_, $rules{$_} } sort keys %rules;

    # If there's no global rate set, show the configured default
    unless ( exists $rules{global} ) {
        push @lines, "default: " . $self->{server}->defaultRate;
    }

    $self->multilineResponse( 'Cluster rate limit rules', @lines );
}

### METHOD: cmd_reset_rate( undef )
### Command handler for the C<reset_rate> command.
sub cmd_reset_rate {
    my JobServer::Client $self = shift;
    my $srcclusterid = shift || '';

    $self->{state} = 'reset_rate';
    my ( $rval, $msg );

    if ($srcclusterid) {
        $rval = $self->{server}->resetClusterRateLimit($srcclusterid);
        $msg  = "Reset rate limit for cluster $srcclusterid to $rval";
    }
    else {
        $rval = $self->{server}->resetGlobalRateLimit;
        $msg  = "Reset global rate limit to $rval";
    }

    return $self->okayResponse($msg);
}

### METHOD: cmd_finish( undef )
### Command handler for the C<finish> command.
sub cmd_finish {
    my JobServer::Client $self = shift;
    my $spec = shift or confess "No job specification";
    $self->{state} = 'finish';

    my ( $userid, $srcclusterid, $dstclusterid ) = split /:/, $spec, 3;

    my $msg = $self->{server}->requestJobFinish( $self, $userid, $srcclusterid, $dstclusterid );

    if ($msg) {
        return $self->okayResponse($msg);
    }
    else {
        return $self->errorResponse("Abort");
    }
}

### METHOD: cmd_help( undef )
### Command handler for the C<help> command.
sub cmd_help {
    my JobServer::Client $self = shift;
    my $command = shift || '';

    $self->{state} = 'help';
    my @response = ();

    # Either show help for a particular command
    if ( $command && exists $CommandTable{$command} ) {
        my $cmdinfo = $CommandTable{$command};
        $cmdinfo->{form} ||= '';    # Non-existant form means no args

        @response = (
            "--- $command -----------------------------------",
            "", "  $command $cmdinfo->{form}",
            "", $cmdinfo->{help} || "(undocumented)",
            "", "Pattern:", "  $cmdinfo->{args}", "",
        );
    }

    else {
        my @cmds = map { "  $_" }
            grep { exists $CommandTable{$_}{help} }
            sort keys %CommandTable;

        @response = ( "Available commands:", "", @cmds, "", );
    }

    return $self->multilineResponse( "Help:", @response );
}

### METHOD: cmd_lock( $userid )
### Command handler for the (debugging) C<lock> command.
sub cmd_lock {
    my JobServer::Client $self = shift;
    my $userid = shift;

    # Fetch the job for the requested user if possible
    my $job = $self->{server}->getJobForUser($userid)
        or return $self->errorResponse("No such user '$userid'.");

    if ( $job->isPrelocked ) {
        my $msg =
            sprintf( "User %d already locked for %d seconds.", $userid, $job->secondsSinceLock );
        return $self->errorResponse($msg);
    }

    # Try to lock the user
    my $time = $job->prelock;
    if ($time) {
        my $msg = "User $userid locked at: $time (" . scalar localtime($time) . ")";
        return $self->okayResponse($msg);
    }
    else {
        return $self->errorResponse("Prelocking of user $userid failed.");
    }
}

### METHOD: cmd_clients( undef )
### Command handler for the C<clients> command.
sub cmd_clients {
    my JobServer::Client $self = shift;

    $self->{state} = 'list clients';

    my @lines = map { sprintf '%3d: %s', $_->fdno, $_->state; } $self->{server}->clients;

    return $self->multilineResponse( 'Clients: ', @lines );
}

### METHOD: cmd_subscribe( $type, $args )
### Command handler for the C<subscribe> command.
sub cmd_subscribe {
    my JobServer::Client $self = shift;
    my ( $type, $args ) = @_;

    $self->{state} = "subscribe to $type events";

    my $msg = $self->{server}->subscribe( $self, $type, $args );
    return $self->okayResponse($msg);
}

### METHOD: cmd_unsubscribe( $type )
### Command handler for the C<unsubscribe> command.
sub cmd_unsubscribe {
    my JobServer::Client $self = shift;
    my ($type) = @_;

    $self->{state} = 'unsubscribe from %s events';

    my $msg = $self->{server}->unsubscribe( $self, $type );
    return $self->okayResponse($msg);
}

### METHOD: cmd_handlers( [$type] )
### Command handler for the C<handlers> command.
sub cmd_handlers {
    my JobServer::Client $self = shift;
    my $type = shift || '';

    $self->{state} = 'handlers';

    my $handlers = $self->{server}->handlers($type);
    my @res;

    if ($handlers) {
        @res = stringifyHandlers($handlers);
    }
    else {
        @res = ("No handlers registered.");
    }

    $self->multilineResponse( "Handlers:", @res );
}

### METHOD: cmd_quit( undef )
### Command handler for the C<quit> command.
sub cmd_quit {
    my JobServer::Client $self = shift;

    $self->{state} = 'quitting';

    $self->okayResponse("Goodbye");
    $self->close;

    return 1;
}

### METHOD: cmd_debuglevel( [$newLevel] )
### Command handler for the C<debuglevel> command.
sub cmd_debuglevel {
    my JobServer::Client $self = shift;
    my $level = shift;

    $self->{state} = 'debuglevel';
    my $msg = '';

    if ( defined $level ) {
        my $oldLevel = $self->{server}->debugLevel;
        my $newLevel = $self->{server}->debugLevel($level);
        $msg = "Debug level was $oldLevel; now $newLevel";
    }

    else {
        $msg = "Debug level is " . $self->{server}->debugLevel;
    }

    return $self->okayResponse($msg);
}

### METHOD: cmd_shutdown( undef )
### Command handler for the C<shutdown> command.
sub cmd_shutdown {
    my JobServer::Client $self = shift;

    $self->{state} = 'shutdown';

    my $msg = $self->{server}->shutdown($self);
    $self->{server} = undef;
    $self->okayResponse($msg);
    $self->close;

    return 1;
}

### METHOD: cmd_timedbuffer( undef )
### Command handler for the C<timedbuffer> command. FOR DEBUGGING ONLY.
sub cmd_timedbuffer {
    my JobServer::Client $self = shift;

    $self->{state} = 'timedbuffer';
    my @jobs = $self->{server}->recentmoves;

    my $count   = 1;
    my @entries = map { sprintf '%3d. %s', $count++, $_->prettyString } @jobs;
    return $self->multilineResponse( "Server's timedbuffer:", @entries );
}

### Template for new command handlers:

# ### METHOD: cmd_foo( undef )
# ### Command handler for the C<foo> command.
# sub cmd_foo {
#     my JobServer::Client $self = shift;
#
#     $self->{state} = 'foo';
#     return $self->errorResponse( "Not yet implemented." );
# }
#
#

1;

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
