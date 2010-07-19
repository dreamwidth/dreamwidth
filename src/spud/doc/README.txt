SPUD -- Statistic Polling and Updating Daemon
        System Productivity and Utilization Daemon
        ...or something

-- Introduction --
SPUD is a set of programs that are designed to collect statistics using
a variety of methods that are easily extendable to gather information on
almost anything you could want to get statistics on.  It then stores these
bits of data in a simple hash server that supports retrieving data enmasse
as well as subscribing to update events.


-- The Components --
There are several pieces to the system:

 - server
   A simple server that stores key/value pairs with 100 data points
   of history.

 - gatherer
   The program that gathers the actual numbers and puts them in a
   stats-server.

 - replicator
   Works in conjunction with a properly configured SSH daemon and the
   cmdshell utility to get stats from one secure network to another.

 - wrapper
   A little script that effectively "wraps" another shell command and
   pipes its STDOUT/STDERR to appropriately named keys on the server.
   Also keeps track of the start/end times of the last time the command
   ran.

 - cmdshell
   A simple utility program that works with stats-replicator.

For more information on each component, please see the various
configuration files in the conf directory as well as the opening comments
of each program.  They are fairly well described in there.


-- Setup --
More documentation to come after the bugs are worked out and the system is
actually setup and in use.  But, in general:

1. Run a stats-server in your internal network somewhere and note the port.

2. Setup the stats.conf for the statistic gatherers.  Then run it once on
a machine that's got some spare time to do gathering.  Make sure to point
this configuration's config files at the server from step 1.

3. Setup an SSH daemon and dummy account on a border machine that you can
get to from the outside world and that can also see the internal network.
Set the shell of the dummy user to cmdshell and configure cmdshell.  Also
setup the authorized_keys file appropriately.  You will want a command
(e.g. replicator) that points at the server setup in step 1.

4. Setup a second stats-server on your local machine/network.  Note down
the port again.

5. Setup the stats-local.conf on your local end to point to the SSH daemon
that you setup in step 3.  Now run the replicator and point it at this
config file and it will start copying data from the first stats server to
the second.

That's it.  Now get some statistics displayers and all of the data gathered
and put onto the first server will be replicated over to the second server.
