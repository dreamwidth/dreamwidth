#!/usr/bin/perl -w
# LiveJournal statistics server. Sits on a UDP port and journals
# information on the incoming hit rate, manages site bans, etc.
# Loosely based on the ljrpcd code to save typing ;)
# <LJDEP>
# lib: IO::Socket Proc::ProcessTable IO::Handle DBI
#
# </LJDEP>

use strict;
use IO::Socket;
use IO::Handle;
use Proc::ProcessTable;
use DBI;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

# Max message length and port to bind.
my $MAXLEN = 512;
my $PORTNO = 6200;
my $PIDFILE = '/home/lj/var/statserv.pid';
my $LOGDIR = '/home/lj/logs/';

# Maximum amount of hits they can use in five minutes.
my %maxes = ( 'ip' => 15, 'guest' => 20, 'user' => 25 );

# Pid and pidfile.
my $pid;
my $is_parent = 1;
# Socket. Needs to be here for the HUP stuff.
my $sock;
# Cache hash.
my %caches = ();
# Cache array.
my @events = ();

# Exceptions hash (IP range or username as keys)
# If you want some host (such as a big stupid random proxy) to
# be more lenient with the number of hits it can make in five minutes,
# put the value in here. If value is -1, then there is no limit.
my %except = ();

# In case we're shot, unlink the pidfile.
$SIG{TERM} = sub {
    unlink($PIDFILE);
    exit 1;
};

# Local network bind to.
my $MYNET = '10.0';

if (-e $PIDFILE) {
    open (PID, $PIDFILE);
    my $tpid;
    chomp ($tpid = <PID>);
    close PID;
    my $processes = Proc::ProcessTable->new()->table;
    if (grep { $_->cmndline =~ /statserv/ } @$processes) {
        print "Process exists already, quitting.\n";
        exit 1;
    }
}

print "LiveJournal Statistics Daemon starting up into the background...\n";

if ($pid = fork) {
  # Parent, log pid and exit.
  open(PID, ">$PIDFILE")   or die "Couldn't open $PIDFILE for writing: $!\n";
  print PID $pid;
  close(PID);
  print "Closing ($pid) wrote to $PIDFILE\n";
  $is_parent = 1;
  exit;
} else {
  # This is the child.
  my($cmdmsg, $remaddr, $remhost);

  # HUP signal handler.
  $SIG{HUP} = \&restart_request;
  # SIGUSR handler.
  $SIG{USR1} = sub { open_logfile(); };

  open_logfile();

  $sock = IO::Socket::INET->new(LocalPort => "$PORTNO", Proto => 'udp')	or die "socket: $@";

  # Main loop.
  while ($sock->recv($cmdmsg, $MAXLEN)) {
    my ($port, $ipaddr) = sockaddr_in($sock->peername);
    my $ip_addr = inet_ntoa($ipaddr);

    # Make sure it's from around here.
    if ($ip_addr !~ m/^$MYNET/) {
      print "Got message from an invalid host.\n";
      next;
    }

    # Quick command parsing, since there isn't much to it.
    if ($cmdmsg =~ s/^cmd:\s//) {
        handle_request($cmdmsg);
        next;
    }
  }
  die "recv: $!\n";
} 

# Sub to restart the daemon.
sub restart_request {
  $sock->close;
  unlink($PIDFILE);
  exec($0);
}


# Handle the request. This updates the appropriate caches,
# and may set a ban.
# Requests look like:
# cmd: cachename : ip_addr : type : url
# type can be: ip, guest, or user
# If type is "ip" then cachename can be anything. I suggest 
# it be set to "ip" as well. If just to save space.
sub handle_request {
  my $cmd = shift;
  my $now = time();

  # Clear expired events.
  clean_events($now);
  # As of now, we don't care about the URL, really.
  if ($cmd =~ m/^(\w+)\s:\s([\d\.]+)\s:\s(\w+)/) {
      my $user = $1;
      my $ip_addr = $2;
      my $type = $3;
      # If there was no cookie of any kind, the type 
      # name is set to "ip" - in this case we up the
      # cache number for the IP range. 
      if ($type eq "ip") {
          # This regex is dumb, but the data we have is trustable.
          $user = $ip_addr;
          $user =~ s/(\d+)\.(\d+)\.(\d+)\.(\d+)/$1\.$2\.$3\./;
      }
      unless (exists $caches{$user}) {
          $caches{$user} = { 'numhit' => 0, 'type' => $type };
      }
      push @events, [ $user, $now ];
      $caches{$user}->{'numhit'}++;

      # Now we check to see if they have hit too fast, and ban if so.
      if (should_ban($user)) {
          # FIXME: For final operation, this should be replaced with
          # a call to set_ban(). This is also going to spam a ton,
          # but with the "spiffy" algorithm I can't easily nuke a user.
          print "Would have banned user $user. Hits: " . $caches{$user}->{'numhit'} . "\n";
      }
      # After this, "add_stat($user, $type, $url)" should run.
  } else {
      print "Got a mal-formed request: $cmd\n";
  }

}

# Returns 1 if the passed "user" should be banned, 0 if not.
sub should_ban {
    my $user = shift;

    my $max = $except{$user} || $maxes{$caches{$user}->{'type'}} || 0; 
    # If it doesn't have a defined class, do we really want it around?
    return 1 unless ($max);
    return 1 if ($caches{$user}->{'numhit'} > $max);

    return 0;
}

# Removes old events, and decrements caches.
sub clean_events {
    my $now = shift;
    while (@events && $events[0]->[1] < $now - 360) {
        my $deadevt = shift @events;
        if (--$caches{$deadevt->[0]}->{'numhits'} < 1) {
            delete $caches{$deadevt->[0]};
        }
    }
}

# Placeholder. Sets a ban in the database.
sub set_ban {

}

# Placeholder. Runs various stats collections.
sub add_stat {

}

# Opens a new tagged logfile. Also sets it to the default
# filehandle, sets autoflush, and returns the new handle.
sub open_logfile {
    my $now = time();
    my $logname = $LOGDIR . "statserv-" . $now . "\.log\n";
    my $logfh = new IO::Handle;
    open($logfh, ">> $logname") or die "Couldn't open $logname: $!\n";
    my $oldfh = select($logfh);
    # Make sure the old one is closed.
    close($oldfh);
    # Set autoflush and return.
    $| = 1;
    return $logfh;
}
