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

umover - User shuffling daemon

=head1 SYNOPSIS

  $ umover OPTIONS MOVECOMMAND
  $ umover OPTIONS COMMANDFILE
  $ umover --unlock

=head2 OPTIONS

=over 4

=item -h, --help

Output a help message and exit.

=item -d, --debug

Output debugging information in addition to normal progress messages.

=item -t, --test

Just test the mover code, don't actually move anyone.

=item -v, --verbose

Output verbose progress information.

=item -T, --threads=<count>

Specify how many threads (subprocesses) to start with for the move. Settings in
C<$ENV{LJHOME}/var/mover-workers> are overridden by this setting.

=item -u,--unlock

Run a query against the mover's "in-progress" table, confirming movers listed
there are still active. This can be run either standalone (i.e., with no
I<MOVECOMMAND> or I<COMMANDFILE>, or as part of a mover run, in which case it
will do an unlock cycle before starting to move anything itself.

=head2 MOVECOMMAND

Move commands are in the form:

  <src clusters>[+active[(<number>)]] to <dest clusters> [<max users>]

=over 4

=item B<src clusters>

A comma-delimited list of clusters or cluster ranges from which to move
users.

Example:

  30-33, 35, 39

=item B<+active>

If this option is given, only active users will be moved. You can specify the
number of days to consider "active" by appending a number in parentheses, e.g.,

  active(20)

means that "active" means activity within the last 20 days. If not specified,
the default of 30 is used.

=item B<dest clusters>

Like B<src clusters>, another comma-delimited list of clusters or cluster
ranges, but specifying the clusters which users will be moved to.

=item B<max users>

A number which serves as an upper limit on the number of users to move in this
run.

=back

=head2 Examples

Move active users from clusters 30-33, 35, and 39 to clusters 40-45.

  30-33, 35, 39 +active to 40-45

Move 10000 users from cluster 18 to clusters 20-24, distributing them evenly
between destination clusters.

  18 to 20-24 10000

=head2 COMMANDFILE

This is the name of a file that contains one or more of the above
L<MOVECOMMAND>s. Each line will be executed in turn.

=head1 REQUIRES

I<Token requires line>

=head1 DESCRIPTION

This is a command-line tool which does mass user-move operations between various
clusters. It just drives multiple invocations of $LJHOME/bin/moveucluster.pl.

=head1 AUTHOR

Michael Granger E<lt>ged@FaerieMUD.orgE<gt>

Copyright (c) 2003 Danga Interactive. All rights reserved.

=cut

##############################################################################
package umover;
use strict;
use warnings qw{all};

use lib "$ENV{LJHOME}/extlib/lib/perl5";

###############################################################################
###  I N I T I A L I Z A T I O N
###############################################################################
BEGIN {

    # Turn STDOUT buffering off
    $| = 1;

    # Versioning stuff and custom includes
    use vars qw{$VERSION $RCSID $AUTOLOAD};
    $VERSION    = do { my @r = (q$Revision: 3660 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    $RCSID      = q$Id: ljumover.pl 3660 2004-02-13 07:24:32Z avva $;

    # Define some constants
    use constant TRUE   => 1;
    use constant FALSE  => 0;

    # Modules
    use Getopt::Long        qw{GetOptions};
    use Pod::Usage          qw{pod2usage};
    use IO::File            qw{};
    use Fcntl               qw{O_RDONLY};
    use Digest::MD5         qw{md5_base64};
    use Data::Dumper        qw{};
    use IO::Socket          qw{};
    use Sys::Hostname       qw{hostname};
    use Time::HiRes         qw{gettimeofday};

    # LiveJournal functions
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    # Turn on option bundling (-vid)
    Getopt::Long::Configure( "bundling" );

    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 0;
}


sub runCommand ($$$$$$);
sub parseCommand ($);
sub parseCluster ($);
sub cleanup ();
sub unlockStaleUsers ();
sub startDaemon ();
sub daemonRoutine ($$);
sub abort (@);


###############################################################################
### C O N F I G U R A T I O N   G L O B A L S
###############################################################################
our (
    $Debug, $VerboseFlag, $ClusterSpecRe, $CommandRe,
    $ReadOnlyBit, $DaemonPid, $MoverWorkersFile, $ActiveDaysDefault,
   );

# -d and -v option flags
$Debug          = FALSE;
$VerboseFlag    = FALSE;

# Patterns for matching movement commands
$ClusterSpecRe  = qr{
                     \d+                        # Lead num
                     (?:\s*-\s*\d+)?            # Range end num (optional)
                     (?:\s*,\s*)?               # Comma + whitespace
                     }x;
$CommandRe      = qr{^
                     ($ClusterSpecRe+)          # Source clusters
                     \s*
                     (\+\s*active
                       (?:\s*\(\s*\d+\s*\))?    # Optional day-range
                     )?                         # Active flag
                     \s+
                     to                         # Literal 'to'
                     \s+
                     ($ClusterSpecRe+)          # Dest clusters
                     (?:\s+(\d+))?              # Maximum
                     $}ix;


# Find the readonly cap class, complain if not found
BEGIN {
    foreach my $bit ( keys %LJ::CAP ) {
        $ReadOnlyBit = $bit, last
            if $LJ::CAP{$bit}{_name} eq '_moveinprogress' &&
                $LJ::CAP{$bit}{readonly} == 1;
    }
    die( "Won't move user without \%LJ::CAP capability class named ",
           "'_moveinprogress' with readonly => 1\n" )
        unless defined $ReadOnlyBit;
}

# The PID of the distributed lock daemon
$DaemonPid      = undef;

# The path to the file that controls the number of running threads.
$MoverWorkersFile = "$ENV{LJHOME}/var/mover-workers";

# The number of days to use as the threshold for activity if the "+active" flag
# is given.
$ActiveDaysDefault = 30;


### Main body
MAIN: {
    my (
        $helpFlag,              # User requested help?
        $testingMode,           # Test-only mode
        $command,               # Command iterator
        $usercount,             # Total users moved
        $threads,               # The number of threads to use while moving
        $unlockMode,            # Run an unlock cycle?
        $instanceId,            # The unique instance id of this mover
        $daemonPid,             # The pid of the distributed lock daemon
        $daemonIp,              # The IP the daemon is listening on
        $daemonPort,            # The ephemeral port the daemon is listening on
        $ifh,                   # Input filehandle
        @commands,              # Move commands
       );

    GetOptions(
        'd|debug+'      => \$Debug,
        'v|verbose'     => \$VerboseFlag,
        'h|help'        => \$helpFlag,
        't|test'        => \$testingMode,
        'T|threads=i'   => \$threads,
        'u|unlock'      => \$unlockMode,
       ) or abortWithUsage();

    # If the -h flag was given, just show the usage and quit
    helpMode() and exit if $helpFlag;
    verboseMsg( "Starting up." );
    $usercount = 0;

    DBI->trace( $Debug - 1 ) if $Debug >= 2;

    unlockStaleUsers() if $unlockMode;

    # Load the commands from a command file
    if ( @ARGV == 1 && -f $ARGV[0] ) {
        debugMsg( "Command-file mode." );
        $ifh = IO::File->new( $ARGV[0], O_RDONLY )
            or abort( "open: $ARGV[0]: $!" );

        while ($command = ($ifh->getline)) {
            next if $command =~ m{^\s*(#.*)?$};
            push @commands, $command;
        }
    }

    # Commands specified on the command line
    elsif ( @ARGV && $ARGV[0] =~ m{^[\d]} ) {
        debugMsg( "Command-line mode." );
        @commands = @ARGV;
    }

    # If -u was given, it's okay to not given any commands
    elsif ( $unlockMode ) {
        exit;
    }

    else {
        abortWithUsage( "Missing or malformed command string/s." );
    }

    ( $instanceId, $daemonIp, $daemonPort ) = startDaemon();

    # Set signal handlers
     $SIG{HUP} = sub { abort "Caught SIGHUP." };
     $SIG{INT} = sub { abort "Interrupted." };
     $SIG{TERM} = sub { abort "Terminated." };

    # Now run the given move commands
    foreach my $command ( @commands ) {
        $usercount += runCommand( $command, $testingMode, $threads,
                                  $instanceId, $daemonIp, $daemonPort );
    }

    # Run any needed cleanup functions
    cleanup();
    message( "Done with all commands. $usercount users moved." );
}


### FUNCTION: cleanup()
### Clean up any children that are still running.
sub cleanup () {
    kill 'TERM', $DaemonPid;
}


#####################################################################
### D A E M O N   ( M U L T I - M O V E R )   F U N C T I O N S
#####################################################################

### FUNCTION: unlockStaleUsers()
### Traverse the clustermove_inprogress table, confirming that each entry
### belongs to an active mover, removing those that don't.
sub unlockStaleUsers () {
    my (
        $sql,                   # SQL query source
        $dbh,                   # Database handle (writer)
        $selsth,                # SELECT statement handle
        $delsth,                # DELETE statement handle
        $row,                   # Selected row hashref
        $sock,                  # Query socket
        %cachedReply,           # Cached replies: {$instance => $bool} (running or not)
       );

    verboseMsg( "Cleaning up the in-progress table." );

    $sql = q{
        SELECT *
        FROM clustermove_inprogress
    };

    # Get a select cursor for the in-progress table
    $dbh = LJ::get_db_writer() or abort( "Couldn't fetch a database handle." );
    $selsth = $dbh->prepare( $sql )
        or abort( "prepare: $sql: ", $dbh->errstr );
    $selsth->execute or abort( "execute: $sql: ", $selsth->errstr );

    # Get a deletion cursor for it too.
    $sql = q{
        DELETE FROM clustermove_inprogress
        WHERE userid = ?
    };
    $delsth = $dbh->prepare( $sql )
        or abort( "prepare: $sql: ", $dbh->errstr );
    $delsth->{ShowErrorStatement} = 1;

    # Fetch each record, connecting to the given host/port for each
    # moverinstance and deleting users for those found not to be running.
    while (( $row = $selsth->fetchrow_hashref )) {
        my ( $host, $port, $instance, $userid ) =
            @{$row}{'moverhost','moverport','moverinstance','userid'};
        my $ip = join '.',
            reverse map { ($host >> $_ * 8) & 0xff } 0..3;

        # If the host hasn't been contacted yet, do so now
        if ( !exists $cachedReply{$instance} ) {
            debugMsg( "Contacting mover at %s:%d (%s) for user %d",
                      $ip, $port, $instance, $userid );

            # If the connection succeeds and replies with the correct response,
            # then the entry's okay
            if (( $sock = new IO::Socket::INET("$ip:$port") )) {
                my $reply = $sock->getline;
                $sock->close;
                debugMsg( "Got reply '%s' from mover at %s:%d", $reply, $host, $port );
                $cachedReply{$instance} = ($instance eq $reply ? 1 : 0);
            }

            # Connection error
            else {
                debugMsg( "Couldn't open a socket to $ip:$port: $!" );
                $cachedReply{$instance} = '';
            }
        }

        # If the cached value indicates it's an invalid record, delete it.
        if ( !$cachedReply{$instance} ) {
            debugMsg( "Removing stale lock set by %s:%d on %s for uid %d",
                      $host, $port, scalar localtime($row->{locktime}), $userid );
            LJ::update_user( $row->{user}, {raw => "caps=caps^(1<<$ReadOnlyBit)"} );
            $delsth->execute( $userid )
                or abort( "execute: $userid: ", $delsth->errstr );
        } else {
            debugMsg( "Keeping lock set by %s:%d on %s for uid %d",
                      $host, $port, scalar localtime($row->{locktime}), $userid );
        }
    }
    $delsth->finish;
    $selsth->finish;

    return 1;
}


### FUNCTION: startDaemon()
### Start a daemon process on an ephemeral port to support distributed
### moves. This function returns a list which consists of an I<instanceId>, the
### ip address of the listener, and the port of the listener. The I<instanceId>,
### which is a 22-character-long (e.g., MD5 hash in base64) string which
### uniquely identifies this instance, should be used in the 'moverinstance'
### field of the clustermove_inprogress' table when locking users for
### moving. When anything connects to the opened port, the daemon writes its
### I<instanceId> to the socket and shuts the socket down. This function also
### sets $DaemonPid to the process id of the forked child.
sub startDaemon () {
    my (
        $seed,      # The source string for the instance id
        $id,        # The instance id
        $lsock,     # Locking socket
        $host,      # Hostname to listen on
        $ip,        # The ip of the listener socket
        $port,      # The port number the listener socket is listening to
       );

    verboseMsg( "Starting distributed lock daemon." );

    # Create the "instance id"
    $seed = join( ':', $$, (gettimeofday), hostname );
    $id = md5_base64( $seed );

    # Create the listener socket
    $host = hostname();
    $lsock = new IO::Socket::INET(
        Listen      => 4,
        LocalAddr   => $host,
        #LocalPort   => 0,           # Kernel chooses ephemeral port
        Reuse       => 1 )          # SO_REUSEADDR
        or abort( "Could not open listener socket: $!" );

    $ip = sprintf '%vd', $lsock->sockaddr;
    $port = $lsock->sockport;

    if (( $DaemonPid = fork )) {
        debugMsg( "Started daemon (%d) at %s:%d with id = '%s'",
                  $DaemonPid, $ip, $port, $id );
        $lsock->close;
    }

    else {
        LJ::DB::disconnect_dbs();
        daemonRoutine( $lsock, $id );
        exit;
    }

    return ( $id, $ip, $port );
}


### FUNCTION: daemonRoutine( $socket, $instanceId )
### Listen to the given I<socket>, writing the specified I<instanceId> to any
### connecting client.
sub daemonRoutine ($$) {
    my ( $listener, $id ) = @_;

    while (( my $sock = $listener->accept )) {
        $sock->print( $id );
        $sock->shutdown( 2 );
    }
}


#####################################################################
### M O V E R   F U N C T I O N S
#####################################################################

### FUNCTION: runCommand( $cmd )
### Parse the given command and run it, returning the numebr of users that were
### moved.
sub runCommand ($$$$$$) {
    my ( $commandStr, $testingMode, $maxThreads, $id, $ip, $port ) = @_;

    my (
        $cmd,
        $mover,
        $count,
       );

    debugMsg( "Parsing command '$commandStr'." );
    $cmd = parseCommand( $commandStr );
    debugMsg( "Parsed command: %s", $cmd );

    $mover = new Mover (
        sources         => $cmd->{sources},
        dests           => $cmd->{dests},
        max             => $cmd->{max},
        activeUsersOnly => $cmd->{active},
        activeDays      => $cmd->{activeDays} || $ActiveDaysDefault,
        chunksize       => 500,
        debugFunction   => \&debugMsg,
        messageFunction => \&verboseMsg,
        testingMode     => $testingMode,
        maxThreads      => $maxThreads,
        instanceId      => $id,
        lockIp          => $ip,
        lockPort        => $port,
       );
    message( 'Moving users%s: %s',
             $testingMode ? " (testing mode)" : "", $mover->desc );
    $count = $mover->start;
    message( 'Done with %s: %d users.',
             $mover->desc, $count );

    return $count;
}


### FUNCTION: parseCommand( $cmd )
### Parse the specified command into a usable command spec, which is returned as
### a hashref.
sub parseCommand ($) {
    my $command = shift or die "No command specified";

    my (
        $srcClusters,
        @sources,
        $activeFlag,
        $activeDays,
        $dstClusters,
        @dests,
        $max,
       );

    unless ( $command =~ $CommandRe ) {
        abort( "Could not parse command '$command'" );
        return undef;
    }

    ( $srcClusters, $activeFlag, $dstClusters, $max ) = ( $1, $2, $3, $4 );
    debugMsg( "Matched: %s", [$srcClusters, $activeFlag, $dstClusters, $max] );

    # Parse source clusters
    foreach my $cluster ( split(/\s*,\s*/, $srcClusters) ) {
        push @sources, parseCluster( $cluster );
    }

    # Parse destination clusters
    foreach my $cluster ( split(/\s*,\s*/, $dstClusters) ) {
        push @dests, parseCluster( $cluster );
    }

    # Grab the "days" param from the "active" flag if both were present
    if ( $activeFlag && $activeFlag =~ m{(\d+)} ) {
        $activeDays = int( $1 );
    }

    my $rval = {
        sources     => \@sources,
        active      => $activeFlag ? TRUE : FALSE,
        activeDays  => $activeDays,
        dests       => \@dests,
        max         => $max || 0,
    };

    debugMsg( "Parsed command '%s' into: %s", $command, $rval );
    return $rval;
}


### FUNCTION: parseCluster( $clusterSpec )
### Parse the given I<clusterSpec> into an list of cluster numbers and return
### them.
sub parseCluster ($) {
    my $cluster = shift;
    die "No cluster specified" unless defined $cluster;
    my @rval = ();

    $cluster =~ s{\s+}{}g;

    if ( $cluster =~ m{^(\d+)-(\d+)$} ) {
        push @rval, ($1 .. $2);
    } elsif ( $cluster =~ m{^(\d+)$} ) {
        push @rval, $1;
    } else {
        error( "Unable to parse cluster: $cluster" );
    }

    debugMsg( "Parsed cluster '%s' into: %s", $cluster, \@rval );
    return @rval;
}


### Kill the daemon process if it's defined and alive
END {
  if ( $DaemonPid ) {
      kill 'TERM', $DaemonPid;
  }
}




#####################################################################
### U T I L I T Y   F U N C T I O N S
#####################################################################

### FUNCTION: helpMode()
### Exit normally after printing the usage message
sub helpMode {
    pod2usage( -verbose => 1, -exitval => 0 );
}


### FUNCTION: abortWithUsage( $message )
### Abort the program showing usage message.
sub abortWithUsage {
    my $msg = join '', @_;

    if ( $msg ) {
        pod2usage( -verbose => 1, -exitval => 1, -message => "$msg" );
    } else {
        pod2usage( -verbose => 1, -exitval => 1 );
    }
}


### FUNCTION: message( @messages )
### Concatenate and print the specified messages.
sub message {
    my ( $format, @args ) = @_;
    printf STDERR "$format\n", @args;
}


### FUNCTION: verboseMsg( @messages )
### Concatenate and print the specified messages if verbose output is turned on.
sub verboseMsg {
    return unless $VerboseFlag;
    message( @_ );
}


### FUNCTION: error( @messages )
### Print the specified messages to the terminal's STDERR.
sub error {
    my $message = @_ ? join '', @_ : '[Mark]';
    print STDERR "ERROR >>> $message <<<\n";
}


### FUNCTION: debugMsg( @messages )
### Print the specified messages to the terminal if debugging mode is activated.
sub debugMsg {
    return unless $Debug;
    my $format = shift;
    chomp( $format );

    my @args = map {
        ref $_
            ? Data::Dumper->Dumpxs([$_])
            : $_;
    } @_;

    my $message = sprintf( $format, @args );
    print STDERR "DEBUG> $message\n";
}


### FUNCTION: abort( @messages )
### Print the specified messages to the terminal and exit with a non-zero status.
sub abort (@) {
    my $msg = @_ ? join '', @_ : "unknown error";
    print STDERR "Aborted: $msg.\n\n";

    exit 1;
}


#####################################################################
### M O V E R   C L A S S
#####################################################################
package Mover;

BEGIN {
    # LiveJournal functions
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    use vars qw{$AUTOLOAD};

    use Carp        qw{confess croak};
    use Time::HiRes qw{usleep};
    use POSIX       qw{:sys_wait_h};
}


### METHOD: new( %args )
### Create a new Mover object configured with the given I<args>.
sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless {
        sources           => [],
        dests             => [],
        max               => 0,
        activeUsersOnly   => 0,
        activeDays        => 30,
        chunksize         => 500,
        maxThreads        => 0,
        moverWorkersMtime => 0,

        userThreads       => {},
        activeThreads     => {},
        fakeMovedUsers    => {},

        debugFunction     => undef,
        messageFunction   => undef,
        debugMode         => 0,

        instanceId        => undef,
        lockIp            => undef,
        lockPort          => undef,

        _signals          => {},
        _haltFlag         => 0,
        _shutdownFlag     => 0,
        _lastStat         => 0,

        %args,
    }, $class;

    return $self;
}


### METHOD: desc()
### Return a description of the lock object.
sub desc {
    my $self = shift or confess "Cannot be called as a function";

    return sprintf( '[%s]%s -> [%s] (Max: %s, Chunksize: %d)',
                    join(',', @{$self->{sources}}),
                    $self->{activeUsersOnly}
                        ? " (Active $self->{activeDays} days)"
                        : "",
                    join(',', @{$self->{dests}}),
                    $self->max,
                    $self->chunksize,
                   );
}


### METHOD: debugMsg( @args )
### If the 'debugFunction' attribute of the mover object is set, call it with
### the specified I<args>.
sub debugMsg {
    my $self = shift or confess "Cannot be called as a function";
    return unless $self->{debugFunction};
    $self->{debugFunction}( @_ );
}


### METHOD: message( @args )
### If the 'messageFunction' attribute of the mover object is set, call it with
### the specified I<args>.
sub message {
    my $self = shift or confess "Cannot be called as a function";
    return unless $self->{messageFunction};
    $self->{messageFunction}( @_ );
}


### METHOD: start( [$max] )
### Start moving users. If I<max> is specified, quit after the specified number
### are moved. Returns the number of users moved.
sub start {
    my $self = shift or confess "Cannot be called as a function";

    my (
        $maxUsers,
        $count,
        $scale,
        $maxThreads,
        $oldMax,
        $chunksize,
        @users,
        @queue,
        $thread,
        $uid,
        $pid,
        $dest,
        $dbh,
       );

    $maxUsers = $self->max || 1e+33;
    $maxThreads = $oldMax = $self->{maxThreads};
    $chunksize = $self->chunksize;
    $chunksize = $maxUsers if $maxUsers < $chunksize;
    $count = 0;
    $self->setSignalHandlers;

    # Iterate over all users for this worker's cluster list, $chunksize per
    # cluster at a time.
  USER: while ( !$self->{_haltFlag} && !$self->{_shutdownFlag} && $count < $maxUsers )
        {
            # Re-read the thread config each time
            $maxThreads = $self->getMaxThreads( $maxThreads );
            $self->debugMsg( "User loop: max threads: $maxThreads" );

            # Advise the use if the thread count changes.
            if ( defined $oldMax && $maxThreads != $oldMax ) {
                $self->message( "Set thread count to %d (was %d)", $maxThreads, $oldMax );
                $oldMax = $maxThreads;
            }

            # No need to do any of the rest if there's no threads to run 'em.
            unless ( $maxThreads ) {
                $self->message( "Idling (threads = 0)." );
                $self->reapChildren;
                sleep 10;
                next USER;
            }

            # Fetch users if the buffer isn't already populated
            unless ( @users ) {
                @users = $self->getPendingUsers( $chunksize )
                    or last USER;
                $self->message( "Fetched %d pending users.", scalar @users );
            }

            # Splice off some users to prepare for moving. Never splice off more
            # than the maximum number of users for this run
            $scale = $maxThreads * 3;
            $scale = ($maxUsers - $count) if ($count + $scale) > $maxUsers;
            @queue = splice( @users, 0, $scale );

            # Now wrap a thread object around each user in the queue, which also
            # locks each one.
            @queue = map {
                my $userRecord = $_;
                last USER if $self->{_haltFlag} || $self->{_shutdownFlag};
                $dest = $self->pickDestination;
                $self->debugMsg( "Creating a thread for user '%s' (%d -> %d)",
                                 $userRecord->{user}, $userRecord->{clusterid},
                                 $dest );

                # Create a mover thread (sets the user's read-only bit).
                $self->{userThreads}{$userRecord->{userid}} =
                    Mover::Thread->new( @{$userRecord}{'user','userid','clusterid'}, $dest );
            } @queue;

            # Wait for the read-only bit to sink in
            $self->debugMsg( "Waiting for read-only bit to sink in." );
            sleep 3;

            # Iterate over the thread objects, forking each one off as the
            # number of active ones falls below the maximum allowed.
          THREAD: foreach my $thread ( @queue ) {
                last USER if $self->{_haltFlag};

                # Wait until more threads can be started
                until ( keys %{$self->{activeThreads}} < $maxThreads ) {
                    last USER if $self->{_haltFlag} || $self->{_shutdownFlag};
                    $self->reapChildren;
                    usleep 0.5;
                }

                # Mark the user as "in progress" by setting the destination
                # cluster field. :FIXME: This is obviously stupid to disconnect
                # and reconnect every time, but since the handle is b0rked after
                # the ->run() below fork()s, this is necessary for it to work.
                LJ::DB::disconnect_dbs();
                $dbh = LJ::get_db_writer()
                    or die "Couldn't fetch a writer.";
                $dbh->do(q{
                    UPDATE clustermove_inprogress SET dstclust = ? WHERE userid = ?
                }, undef, $thread->dest, $thread->userid )
                    or die "Failed to update lock: ", $dbh->errstr;

                # Run the thread
                $count++;
                $thread->testingMode( $self->testingMode );
                $self->message( "Moving user '%s' (#%d): src %d -> dst %d (count: %d)",
                                $thread->user, $thread->userid, $thread->src,
                                $thread->dest, $count );
                $pid = $thread->run;
                $self->{activeThreads}{ $pid } = $thread;
                $self->reapChildren;
            }

            $self->reapChildren;
        }

    if ( $self->{_haltFlag} ) { $self->message( ">>> Halted by signal <<<" ) }
    elsif ( $self->{_shutdownFlag} ) { $self->message( ">>> Shutdown by signal <<<" ) }
    else { $self->debugMsg( "Done with thread loop." ); }

    $self->restoreSignalHandlers;

    # Handle threads that are still running
    if ( %{$self->{activeThreads}} ) {

        # Let children finish unless the process is being forcefully shut down.
        unless ( $self->{_haltFlag} ) {
            foreach ( 1..10 ) {
                last unless %{$self->{activeThreads}};
                $self->message( "Waiting for %d remaining children to finish.",
                                scalar keys %{$self->{activeThreads}} );

                $self->reapChildren;
                sleep 1;
            }
        }

        # Kill off any remaining children if there are any
        foreach my $signal ( 'TERM', 'QUIT', 'KILL' ) {
            last unless %{$self->{activeThreads}};

            $self->message( "Sending SIG%s to remaining %d threads.",
                            $signal, scalar keys %{$self->{activeThreads}} );
            foreach my $pid ( keys %{$self->{activeThreads}} ) {
                kill $signal, $pid if exists $self->{activeThreads}{ $pid };
            }

            $self->reapChildren;
        } continue {
            sleep 2;
        };
    }

    # Unlock any users that didn't get moved
    if ( %{$self->{userThreads}} ) {
        $self->message( "Unlocking %d remaining users.", values %{$self->{userThreads}} );

        foreach my $thread ( values %{$self->{userThreads}} ) {
            LJ::DB::disconnect_dbs();
            $thread->unlock;
            my $dbh = LJ::get_db_writer() or die "Couldn't get a db_writer.";
            $dbh->do( "DELETE FROM clustermove_inprogress WHERE userid = ?",
                      undef, $thread->userid )
                or die "Failed to delete user ", $thread->userid,
                    " from the in-progress table: ", $dbh->errstr;
        }
    }

    return $count;
}


### METHOD: reapChildren()
### Collect any child processes that have died. Returns the number of processed
### reaped.
sub reapChildren {
    my $self = shift or confess "Cannot be called as a function";
    my $count = 0;

    # Reap any child processes that need it and delete the corresponding thread
    # object from the thread table. Delete the user from the user => thread map
    # unless the thread is in testing mode (ie., doesn't actually remove the
    # user from the source table).
    while ((my $pid = waitpid( -1, WNOHANG )) > 0) {
        next if $pid == $DaemonPid;
        my $thread = delete $self->{activeThreads}{ $pid };
        $self->{fakeMovedUsers}{$thread->userid} = 1 if $thread->testingMode;
        delete $self->{userThreads}{$thread->userid};

        LJ::DB::disconnect_dbs();
        $thread->unlock;
        my $dbh = LJ::get_db_writer() or die "Couldn't get a db_writer.";
        $dbh->do( "DELETE FROM clustermove_inprogress WHERE userid = ?",
                  undef, $thread->userid )
            or die "Failed to delete user ", $thread->userid,
                " from the in-progress table: ", $dbh->errstr;

        $self->debugMsg( "Reaped child %d (uid: %d, exit: %d). %d process/es remain.",
                         $pid, $thread->userid, $?,
                         scalar keys %{$self->{activeThreads}} );
        $count++;
    }

    return $count;
}


### METHOD: pickDestination()
### Pick a destination cluster for the given user.
sub pickDestination {
    my $self = shift or confess "Cannot be called as a function";

    # Pick a destination, then rotate the list.
    my $dest = $self->{dests}[0];
    push( @{$self->{dests}}, shift @{$self->{dests}} );

    return $dest;
}


### METHOD: getPendingUsers()
### Return users that need moving from the source clusters for this mover.
sub getPendingUsers {
    my $self = shift or confess "Cannot be called as a function";
    my $limit = shift || 500;

    my (
        $sql,       # SQL query string
        $dbh,       # Database handle (writer)
        $ipsth,     # INSERT cursor for the in-progress table
        $seldbh,    # Database handle (cluster master for active users, copy of
                    # $dbh if not)
        $selsth,    # User-selection cursor
        $iip,       # Integer IP for insertion into the in-progress table
        $row,       # Row iterator
        @users,     # User rows
       );

    # :FIXME: This is the only way I can make this query work. If I don't do
    # this, I get "MySQL has gone away" on the second query, despite calling
    # disconnect_dbs() in the thread's start() method immediately after the
    # fork(), too. Perhaps I'll revisit this after hacking on DBI::Role for a
    # bit.
    LJ::DB::disconnect_dbs();
    $dbh = LJ::get_db_writer() or die "failed to get_db_writer()";

    $sql = q{
        INSERT INTO clustermove_inprogress
            ( userid, locktime, moverhost, moverport, moverinstance )
        VALUES
            (      ?,        ?,         ?,         ?,             ? )
    };
    $ipsth = $dbh->prepare( $sql ) or die "prepare: ", $dbh->errstr;

    # Pick a query based on whether the user wants only active users.
    if ( $self->activeUsersOnly ) {
        $sql = sprintf q{
            SELECT
                userid
            FROM
                clustertrack2
            WHERE
                timeactive > UNIX_TIMESTAMP() - 86400*%d
                AND clusterid = ?
            LIMIT %d
        }, $self->activeDays, $limit;
    } else {
        $sql = sprintf q{
            SELECT
                user,
                userid,
                statusvis,
                clusterid
            FROM user
            WHERE clusterid = ?
            LIMIT %d
        }, $limit;
    }

    $iip = unpack( 'N', pack('C4', split( /\./, $self->lockIp )) );
    @users = ();

    # Fetch users for each cluster
    foreach my $cid ( @{$self->{sources}} ) {

        # Either get the cluster master handle for active users, or reuse the
        # current one for all users
        $seldbh = $self->activeUsersOnly ? LJ::get_cluster_master($cid) : $dbh;
        die "Couldn't obtain db handle for cluster $cid\n" unless $seldbh;

        # Prepare the selection cursor and execute it
        $selsth = $seldbh->prepare( $sql ) or die "prepare: ", $seldbh->errstr;
        $self->debugMsg( "Running user-select query '%s' on cluster %d", $sql, $cid );
        $selsth->execute( $cid ) or die "execute: ", $selsth->errstr;

        while (( $row = $selsth->fetchrow_hashref )) {
            next if exists $self->{userThreads}{$row->{userid}}
                or exists $self->{fakeMovedUsers}{$row->{userid}};

            # populate the rest of the row
            if ($self->activeUsersOnly) {
                my $u = LJ::load_userid($row->{userid}, "force");
                die "Couldn't load userid: $row->{userid}" unless $u;

                # if for some reason this user had a clustertrack2 row they shouldn't have,
                # delete the clustertrack2 on this cluster and move along.
                if ($u->{'clusterid'} != $cid) {
                    $seldbh->do("DELETE FROM clustertrack2 WHERE userid=? AND clusterid=?",
                                undef, $u->{userid}, $cid);
                    print("deleted invalid clustertrack2 for userid=$u->{userid} ",
                          "(not cluster $cid, but $u->{clusterid}\n");
                    next;
                }

                $row = $u;
            }

            # Insert the user in the in-progress table, skipping users who're
            # already being moved by another mover
            next unless
                $ipsth->execute( $row->{userid}, time, $iip,
                                 $self->lockPort, $self->instanceId );

            $self->debugMsg( "Selected row: %s", $row );
            push @users, {%$row};
        } continue {
            $self->debugMsg( "DBI error: %s", $DBI::errstr ) if $DBI::errstr;
        }
    }

    $ipsth->finish;
    return sort { $a->{userid} <=> $b->{userid} } @users;
}


### METHOD: getMaxThreads()
### Fetch the maximum number of threads from the config file, or return a
### default if the config file doesn't exist or is unreadable.
sub getMaxThreads {
    my $self = shift or confess "Cannot be called as a function";
    my $maxThreads = shift;

    if ( -r $MoverWorkersFile ) {
        $self->{moverWorkersMtime} ||= (stat _)[9];
        my $mtime = $self->{moverWorkersMtime};

        if ( !defined $maxThreads || (stat _)[9] > $mtime ) {
            $self->{moverWorkersMtime} = (stat _)[9];
            $self->message( "(Re)-reading $MoverWorkersFile:\n\t%s < %s",
                            scalar localtime($mtime),
                            scalar localtime($self->{moverWorkersMtime}) );

            # Read the process limit from a file, or default to unlimited
            if ( open my $ifh, $MoverWorkersFile ) {
                chomp( $maxThreads = <$ifh> );
                $maxThreads = int($maxThreads);
            }
        }
    }

    $maxThreads = 1 if !defined $maxThreads;
    return $maxThreads;
}


### METHOD: setSignalHandlers()
### Set up signal handlers to toggle shutdown flags in the object, saving any
### current handlers.
sub setSignalHandlers {
    my $self = shift or confess "Cannot be called as a function";

    $self->debugMsg( "Installing new signal handlers." );
    $self->{_signals}{HUP} = $SIG{HUP};
    $SIG{HUP} = sub { $self->{_shutdownFlag} = 1 };

    $self->{_signals}{INT} = $SIG{INT};
    $SIG{INT} = sub { $self->{_shutdownFlag} = 1 };

    $self->{_signals}{TERM} = $SIG{TERM};
    $SIG{TERM} = sub { $self->{_haltFlag} = 1 };

    return 1;
}


### METHOD: restoreSignalHandlers()
### Restore the signal handlers that were saved by setSignalHandlers().
sub restoreSignalHandlers {
    my $self = shift or confess "Cannot be called as a function";

    $self->debugMsg( "Restoring initial signal handlers." );
    foreach my $signal ( keys %{$self->{_signals}} ) {
        $SIG{$signal} = $self->{_signals}{$signal};
    }

    return 1;
}


### (PROXY) METHOD: AUTOLOAD( @args )
### Proxy method to build object accessors.
sub AUTOLOAD {
    my $self = shift or croak "Cannot be called as a function";
    ( my $name = $AUTOLOAD ) =~ s{.*::}{};

    my $method;

    if ( ref $self && exists $self->{$name} ) {

        # Define an accessor for this attribute
        $method = sub : lvalue {
            my $closureSelf = shift or croak "Can't be used as a function.";
            $closureSelf->{$name} = shift if @_;
            return $closureSelf->{$name};
        };

        # Install the new method in the symbol table
      NO_STRICT_REFS: {
            no strict 'refs';
            *{$AUTOLOAD} = $method;
        }

        # Now jump to the new method after sticking the self-ref back onto the
        # stack
        unshift @_, $self;
        goto &$AUTOLOAD;
    }

    # Try to delegate to our parent's version of the method
    my $parentMethod = "SUPER::$name";
    return $self->$parentMethod( @_ );
}


DESTROY {
    my $self = shift;
    $self->restoreSignalHandlers;
}



#####################################################################
### M O V E R   T H R E A D   C L A S S
#####################################################################
package Mover::Thread;

BEGIN {
    # LiveJournal functions
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    use vars qw{$AUTOLOAD};
    use Carp qw{croak confess};
}


### METHOD: new( $user, $dest )
### Create a mover thread object that will move the specified I<user> to the
### given I<dest> cluster.
sub new {
    my $class = shift;
    my ( $user, $userid, $src, $dest ) = @_;

    # Lock the user
    LJ::DB::disconnect_dbs();
    LJ::update_user( $userid, {raw => "caps=caps|(1<<$ReadOnlyBit)"} );

    return bless {
        userid      => $userid,
        user        => $user,
        src         => $src,
        dest        => $dest,
        pid         => undef,
        testingMode => 0,
        locked      => 1,
    }, $class;
}


### METHOD: run()
### Execute the backend mover.
sub run {
    my $self = shift or confess "Cannot be called as a function";

    # Fork and exec a child, keeping the pid
    unless (( $self->{pid} = fork )) {
        LJ::DB::disconnect_dbs();

        if ( $self->testingMode ) {
            my $seconds = int(rand 20) + 3;
            printf STDERR "Child %d sleeping %d seconds to simulate move.\n",
                $$, $seconds;
            sleep $seconds;
        } else {
            exec( "$ENV{LJHOME}/bin/moveucluster.pl",
                  "--verbose=0",
                  "--expungedel",
                  "--destdel",
                  "--prelocked",
                  $self->user,
                  $self->dest );
        }

        exit;
    }

    return $self->pid;
}


### METHOD: unlock()
### Remove the read-only bit from the user this thread corresponds to.
sub unlock {
    my $self = shift;

    if ( $self->{locked} ) {
        print STDERR "Unlocking user $self->{userid}.\n";
        LJ::update_user( $self->{userid}, {raw => "caps=caps&~(1<<$ReadOnlyBit)"} );
        $self->{locked} = 0;
    }

    return 1;
}


sub DESTROY {}


### (PROXY) METHOD: AUTOLOAD( @args )
### Proxy method to build object accessors.
sub AUTOLOAD {
    my $self = shift or croak "Cannot be called as a function";
    ( my $name = $AUTOLOAD ) =~ s{.*::}{};

    my $method;

    if ( ref $self && exists $self->{$name} ) {

        # Define an accessor for this attribute
        $method = sub : lvalue {
            my $closureSelf = shift or croak "Can't be used as a function.";
            $closureSelf->{$name} = shift if @_;
            return $closureSelf->{$name};
        };

        # Install the new method in the symbol table
      NO_STRICT_REFS: {
            no strict 'refs';
            *{$AUTOLOAD} = $method;
        }

        # Now jump to the new method after sticking the self-ref back onto the
        # stack
        unshift @_, $self;
        goto &$AUTOLOAD;
    }

    # Try to delegate to our parent's version of the method
    my $parentMethod = "SUPER::$name";
    return $self->$parentMethod( @_ );
}


