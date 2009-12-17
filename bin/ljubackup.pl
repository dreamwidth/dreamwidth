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

ljubackup - Per-user backup to mogilefs backend

=head1 SYNOPSIS

  $ ljubackup OPTIONS USERNAME
  $ ljubackup --unlock

=head2 OPTIONS

=over 4

=item -h, --help

Output a help message and exit.

=item -d, --debug

Output debugging information in addition to normal progress messages.

=item -m, --max=<count>

Back up at most I<count> users before terminating.

=item -t, --test

Just test the backup code, don't actually insert the backup db.

=item -v, --verbose

Output verbose progress information.

=item -T, --threads=<count>

Specify how many threads (subprocesses) to start with for the move. Settings in
C<$ENV{LJHOME}/var/backup-workers> are overridden by this setting.

=item -u,--unlock

Run a query against the backup agent's "in-progress" table, confirming agents
listed there are still active before starting backups.

=head1 REQUIRES

I<Token requires line>

=head1 DESCRIPTION

This is a command-line tool which does mass user-backup operations. It drives
multiple invocations of the ljbackup.pl program for users listed in the
C<backupdirty> table.

=head1 AUTHOR

Michael Granger E<lt>ged@FaerieMUD.orgE<gt>

Copyright (c) 2003, 2004 Danga Interactive. All rights reserved.

=cut

##############################################################################
package ljubackup;
use strict;
use warnings qw{all};


###############################################################################
###  I N I T I A L I Z A T I O N
###############################################################################
BEGIN {

    # Turn STDOUT buffering off
    $| = 1;

    # Versioning stuff and custom includes
    use vars qw{$VERSION $RCSID $AUTOLOAD};
    $VERSION    = do { my @r = (q$Revision: 12273 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    $RCSID      = q$Id: ljubackup.pl 12273 2007-08-16 21:58:52Z mischa $;

    # Define some constants
    use constant TRUE   => 1;
    use constant FALSE  => 0;

    use lib ( "$ENV{LJHOME}/cgi-bin" );

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
    use LJ::User            qw{};
    use MogileFS::Client;

    # LiveJournal functions
    use LJ::Config;
    LJ::Config->load;

    # Turn on option bundling (-vid)
    Getopt::Long::Configure( "bundling" );

    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 0;
}

sub backupUsers ($$$$$$);
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
    $Debug, $VerboseFlag, $DaemonPid, $BackupAgentWorkersFile, $ActiveDaysDefault,
   );

# -d and -v option flags
$Debug          = FALSE;
$VerboseFlag    = FALSE;


# The PID of the distributed lock daemon
$DaemonPid      = undef;

# The path to the file that controls the number of running threads.
$BackupAgentWorkersFile = "$ENV{LJHOME}/var/userbackup-workers";

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
		$max,					# Max users to move
        $threads,               # The number of threads to use while backing up
        $unlockMode,            # Run an unlock cycle?
        $instanceId,            # The unique instance id of this invocation
        $daemonPid,             # The pid of the distributed lock daemon
        $daemonIp,              # The IP the daemon is listening on
        $daemonPort,            # The ephemeral port the daemon is listening on
        $ifh,                   # Input filehandle
        $mogfs,                 # MogileFS handle for 'userbackup' domain
        @commands,              # Move commands
       );

    GetOptions(
        'd|debug+'      => \$Debug,
        'v|verbose'     => \$VerboseFlag,
        'h|help'        => \$helpFlag,
		'm|max=i'		=> \$max,
        't|test'        => \$testingMode,
        'T|threads=i'   => \$threads,
        'u|unlock'      => \$unlockMode,
       ) or abortWithUsage();

    # If the -h flag was given, just show the usage and quit
    helpMode() and exit if $helpFlag;
    verboseMsg( "Starting up." );
    $usercount = 0;

    DBI->trace( $Debug - 1 ) if $Debug >= 2;

    # If there's a MogileFS instance, test it for the required domain
    if ( defined %LJ::MOGILEFS_CONFIG ) {
        $MogileFS::DEBUG = $Debug;

        my %mogconfig = ( %LJ::MOGILEFS_CONFIG, domain => 'userbackup' );
        $mogfs = MogileFS::Client->new( %mogconfig )
            or abort( "Couldn't create a MogileFS handle." );
    }

    # Otherwise we can't continue
    else {
        abort( "Requires MogileFS configuration. Check your ljconfig.pl." );
    }

    unlockStaleUsers() if $unlockMode;
    ( $instanceId, $daemonIp, $daemonPort ) = startDaemon();

    # Set signal handlers
     $SIG{HUP} = sub { abort "Caught SIGHUP." };
     $SIG{INT} = sub { abort "Interrupted." };
     $SIG{TERM} = sub { abort "Terminated." };

    # Now run the given move commands
	backupUsers( $mogfs, $testingMode, $threads, $instanceId, $daemonIp, $daemonPort );

    # Run any needed cleanup functions
    cleanup();
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
### belongs to an active process, removing those that don't.
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

    # Fetch each record, connect to the given host/port for each backup agent
    # and deleting entries for those found not to be running.
    while (( $row = $selsth->fetchrow_hashref )) {
        my ( $host, $port, $instance, $userid ) =
            @{$row}{'moverhost','moverport','moverinstance','userid'};
        my $ip = join '.',
            reverse map { ($host >> $_ * 8) & 0xff } 0..3;

        # If the host hasn't been contacted yet, do so now
        if ( !exists $cachedReply{$instance} ) {
            debugMsg( "Contacting process at %s:%d (%s) for user %d",
                      $ip, $port, $instance, $userid );

            # If the connection succeeds and replies with the correct response,
            # then the entry's okay
            if (( $sock = new IO::Socket::INET("$ip:$port") )) {
                my $reply = $sock->getline;
                $sock->close;
                debugMsg( "Got reply '%s' from process at %s:%d", $reply, $host, $port );
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
            my $user = lookup LJ::User $userid;
			$user->make_readwrite;
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
### backup. When anything connects to the opened port, the daemon writes its
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
        LJ::disconnect_dbs();
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

### FUNCTION: backupUsers( $testingMode, $maxThreads,  )
### Parse the given command and run it, returning the numebr of users that were
### moved.
sub backupUsers ($$$$$$) {
    my ( $mogfs, $testingMode, $maxThreads, $id, $ip, $port, $max ) = @_;

    my (
        $cmd,
        $agent,
        $count,
       );

    $agent = new BackupAgent (
        mogilefs        => $mogfs,
        chunksize       => 500,
		maxUsers		=> $max,
        debugFunction   => \&debugMsg,
        messageFunction => \&verboseMsg,
        testingMode     => $testingMode,
        maxThreads      => $maxThreads,
        instanceId      => $id,
        lockIp          => $ip,
        lockPort        => $port,
       );
    message( 'Backing up users%s: %s',
             $testingMode ? " (testing mode)" : "", $agent->desc );
    $count = $agent->start;
    message( 'Done with %s: %d users.',
             $agent->desc, $count );

    return $count;
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
###	B A C K U P A G E N T   C L A S S
#####################################################################
package BackupAgent;

BEGIN {
    # LiveJournal functions
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    use vars qw{$AUTOLOAD};

    use Carp        qw{confess croak};
    use Time::HiRes qw{usleep};
    use POSIX       qw{:sys_wait_h};
}


### METHOD: new( %args )
### Create a new BackupAgent object configured with the given I<args>.
sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless {
        mogilefs          => undef,

        chunksize         => 500,
		maxUsers		  => 0,
        maxThreads        => 0,
        agentWorkersMtime => 0,

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

    return sprintf( 'Backup Agent (chunksize: %d)', $self->{chunksize} );
}


### METHOD: debugMsg( @args )
### If the 'debugFunction' attribute of the agent object is set, call it with
### the specified I<args>.
sub debugMsg {
    my $self = shift or confess "Cannot be called as a function";
    return unless $self->{debugFunction};
    $self->{debugFunction}( @_ );
}


### METHOD: message( @args )
### If the 'messageFunction' attribute of the agent object is set, call it with
### the specified I<args>.
sub message {
    my $self = shift or confess "Cannot be called as a function";
    return unless $self->{messageFunction};
    $self->{messageFunction}( @_ );
}


### METHOD: start( [$max] )
### Start backing up users. If I<max> is specified, quit after the specified
### number are moved. Returns the number of users moved.
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
        $dbh,
       );

    $maxUsers = $self->maxUsers || 1e+33;
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

            # Advise the user if the thread count changes.
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
                @users = $self->getDirtyUsers( $chunksize )
                    or last USER;
                $self->message( "Fetched %d dirty users.", scalar @users );
            }

            # Splice off some users to prepare for backup. Never splice off more
            # than the maximum number of users for this run
            $scale = $maxThreads * 3;
            $scale = ($maxUsers - $count) if ($count + $scale) > $maxUsers;
            @queue = splice( @users, 0, $scale );

            # Now wrap a thread object around each user in the queue, which also
            # locks each one.
            @queue = map {
                my $user = $_;
                last USER if $self->{_haltFlag} || $self->{_shutdownFlag};
                $self->debugMsg( "Creating a thread for user '%s'", $user->user );

                # Create a agent thread (sets the user's read-only bit).
                $self->{userThreads}{$user->userid} =
                    BackupAgent::Thread->new( $self->{mogilefs}, $user );
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

                # :FIXME: Is this necessary? We obviously don't have a
                # destination cluster...

                #LJ::disconnect_dbs();
                #$dbh = LJ::get_db_writer()
                #    or die "Couldn't fetch a writer.";
                #$dbh->do(q{
                #    UPDATE clustermove_inprogress SET dstclust = ? WHERE userid = ?
                #}, undef, 0, $thread->userid )
                #    or die "Failed to update lock: ", $dbh->errstr;

                # Run the thread
                $count++;
                $thread->testingMode( $self->testingMode );
                $self->message( "Backing up user '%s' (#%d) count: %d",
                                $thread->user->user, $thread->user->userid, $count );
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
            $thread->unlock;
            LJ::disconnect_dbs();
            my $dbh = LJ::get_db_writer() or die "Couldn't get a db_writer.";
            $dbh->do( "DELETE FROM clustermove_inprogress WHERE userid = ?",
                      undef, $thread->user->userid )
                or die "Failed to delete user ", $thread->user->userid,
                    " from the in-progress table: ", $dbh->errstr;
        }
    }

    return $count;
}


### METHOD: reapChildren()
### Collect any child processes that have died. Returns the number of processes
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
        $self->{fakeMovedUsers}{$thread->user->userid} = 1 if $thread->testingMode;
        delete $self->{userThreads}{$thread->user->userid};

        $thread->unlock;
        LJ::disconnect_dbs();
        my $dbh = LJ::get_db_writer() or die "Couldn't get a db_writer.";
        $dbh->do( "DELETE FROM clustermove_inprogress WHERE userid = ?",
                  undef, $thread->user->userid )
            or die "Failed to delete user ", $thread->user->userid,
                " from the in-progress table: ", $dbh->errstr;

        $self->debugMsg( "Reaped child %d (uid: %d, exit: %d). %d process/es remain.",
                         $pid, $thread->user->userid, $?,
                         scalar keys %{$self->{activeThreads}} );
        $count++;
    }

    return $count;
}


### METHOD: getDirtyUsers()
### Return users that need backup.
sub getDirtyUsers {
    my $self = shift or confess "Cannot be called as a function";
    my $limit = shift || 500;

    my (
        $sql,       # SQL query string
        $dbh,       # Database handle
        $ipsth,     # INSERT cursor for the in-progress table
        $selsth,    # User-selection cursor
        $iip,       # Integer IP for insertion into the in-progress table
        $row,       # Row iterator
        @userids,   # Ids of users to back up
        @users,     # User objects to back up
		$user,		# User object iterator
       );

    # :FIXME: This is the only way I can make this query work. If I don't do
    # this, I get "MySQL has gone away" on the second query, despite calling
    # disconnect_dbs() in the thread's start() method immediately after the
    # fork(), too. Perhaps I'll revisit this after hacking on DBI::Role for a
    # bit.
    LJ::disconnect_dbs();
    $dbh = LJ::get_db_writer() or die "failed to get_db_writer()";

    $sql = q{
        INSERT INTO clustermove_inprogress
            ( userid, locktime, moverhost, moverport, moverinstance )
        VALUES
            (      ?,        ?,         ?,         ?,             ? )
    };
    $ipsth = $dbh->prepare( $sql ) or die "prepare: ", $dbh->errstr;

    # Pick a query based on whether the user wants only active users.
    $sql = sprintf q{
        SELECT userid
        FROM backupdirty
        ORDER BY marktime ASC
        LIMIT %d
    }, $limit;

    # Prepare the selection cursor and execute it
    $selsth = $dbh->prepare( $sql ) or die "prepare: ", $dbh->errstr;
    $self->debugMsg( "Running user-select query '%s'", $sql );
    $selsth->execute or die "execute: ", $selsth->errstr;

    $iip = unpack( 'N', pack('C4', split( /\./, $self->lockIp )) );

    # Fetch userids
    @userids = grep {
		!exists $self->{userThreads}{$_}
		&& !exists $self->{fakeMovedUsers}{$_}
	} map {
		$_->[0][0]
	} $selsth->fetchall_arrayref([0]);

	# If there are potential users to look up, do so
	if ( @userids ) {
		@users = LJ::User->lookup( @userids );

		for ( my $i = 0; $i <= $#users; $i++ ) {
			# If the user record didn't load, remove it
			unless ( defined($user = $users[$i]) ) {
				$self->debugMsg( "Failed lookup for user $userids[$i]" );
				splice @users, $i, 1;
				splice @userids, $i, 1;
				$i--;
				next;
			}

			# If the user loaded, but won't lock for some reason, remove it
			unless ( $ipsth->execute($user->userid, time, $iip,
									 $self->lockPort, $self->instanceId) )
			{
				$self->debugMsg( "Failed lock for user %s: %s", $user->user, $ipsth->errstr );
				splice @users, $i, 1;
				splice @userids, $i, 1;
				$i--;
				next;
			}

			$self->debugMsg( "Selected user: %s", $user->user );
		}
	}

    $ipsth->finish;
    return @users;
}


### METHOD: getMaxThreads()
### Fetch the maximum number of threads from the config file, or return a
### default if the config file doesn't exist or is unreadable.
sub getMaxThreads {
    my $self = shift or confess "Cannot be called as a function";
    my $maxThreads = shift;

    if ( -r $BackupAgentWorkersFile ) {
        $self->{agentWorkersMtime} ||= (stat _)[9];
        my $mtime = $self->{agentWorkersMtime};

        if ( !defined $maxThreads || (stat _)[9] > $mtime ) {
            $self->{agentWorkersMtime} = (stat _)[9];
            $self->message( "(Re)-reading $BackupAgentWorkersFile:\n\t%s < %s",
                            scalar localtime($mtime),
                            scalar localtime($self->{agentWorkersMtime}) );

            # Read the process limit from a file, or default to unlimited
            if ( open my $ifh, $BackupAgentWorkersFile ) {
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
package BackupAgent::Thread;

BEGIN {
    # LiveJournal functions
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    use vars qw{$AUTOLOAD};
    use Carp qw{croak confess};
	use IO::File qw{};
	use Fcntl qw{O_RDONLY};
}


### METHOD: new( $mogilefs, $user )
### Create a agent thread object that will move the specified I<user> to the
### given I<mogilefs> filestore.
sub new {
    my $class = shift;
    my ( $mogfs, $user ) = @_;

    # Lock the user
    $user->make_readonly;

    return bless {
        mogilefs    => $mogfs,
        user        => $user,
        pid         => undef,
        testingMode => 0,
        locked      => 1,
    }, $class;
}


### METHOD: run()
### Execute the backend backup program.
sub run {
    my $self = shift or confess "Cannot be called as a function";

    # Fork and exec a child, keeping the pid
    unless (( $self->{pid} = fork )) {
        LJ::disconnect_dbs();

		my (
			$user,
			$backfile,
			$mogilekey,
			$ifh,
			$ofh,
			$buf,
		   );

		$user = $self->{user};
		$backfile = sprintf( "ljubackup.%s.%d.%d",
								$user->user,
								$user->userid,
								$$ );
		$mogilekey = sprintf( 'userbackup:%d', $user->userid );

		# In testing mode, run the program with the --dump option
		if ( $self->{testingMode} ) {
			system( "$ENV{LJHOME}/bin/ljbackup.pl", "--dump", $user->user ) == 0
				or die "ljbackup.pl failed: $?";
		}

		# In regular mode, dump the user to a dbm file and then stick that in
		# MogileFS.
		else {
			system( "$ENV{LJHOME}/bin/ljbackup.pl", "--file=$backfile",
					$user->user ) == 0 or die "ljbackup.pl failed: $?";

			# Open the dbm and a new Mogile handle
			$ifh = new IO::File $backfile, O_RDONLY
				or die "open: $backfile: $!";
			$ofh = $self->{mogilefs}->new_file( $mogilekey, 'normal' )
				or die "MogileFS::new_file: ", $self->{mogilefs}->errstr;

			# Copy the data over
			until ( $ifh->eof ) {
				my $bytes = $ifh->read( $buf, 4096 );

				if ( $bytes ) {
					$ofh->print( $buf );
				} elsif ( $!{EAGAIN} ) {
					next;
				} else {
					die "read: $backfile: $!";
				}
			}

			# Make sure it's uploaded correctly
			$ofh->close or die "error saving file to mogile: $@";
			unlink $backfile;
			$user->mark_clean;
		}

		exit 0;
    }

    return $self->pid;
}


### METHOD: unlock()
### Remove the read-only bit from the user this thread corresponds to.
sub unlock {
    my $self = shift;

    if ( $self->{locked} ) {
        print STDERR "Unlocking user ", $self->{user}->userid, ".\n";
        $self->{user}->make_readwrite;
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
    #my $parentMethod = "SUPER::$name";
    #return $self->$parentMethod( @_ );
	croak sprintf q{Can't locate object method "%s" via package "%s"}, $name, ref $self;
}


