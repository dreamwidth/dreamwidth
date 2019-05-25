#!/usr/bin/perl
###########################################################################

=head1 NAME

DDLockClient - Client library for distributed lock daemon

=head1 SYNOPSIS

  use DDLockClient ();

  my $cl = new DDLockClient (
        servers => ['locks.localnet:7004', 'locks2.localnet:7002', 'localhost']
  );

  # Do something that requires locking
  if ( my $lock = $cl->trylock("foo") ) {
    ...do some 'foo'-synchronized stuff...
  } else {
    die "Failed to lock 'foo': $!";
  }

  # You can either just let $lock go out of scope or explicitly release it:
  $lock->release;

=head1 DESCRIPTION

This is a client library for ddlockd, a distributed lock daemon not entirely
unlike a very simplified version of the CPAN module IPC::Locker.

=head1 REQUIRES

L<Socket>

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Brad Fitzpatrick <brad@danga.com>

Copyright (c) 2004 Danga Interactive, Inc.

=cut

###########################################################################

#####################################################################
###     D D L O C K   C L A S S
#####################################################################
package DDLock;
use strict;
use Socket qw{:DEFAULT :crlf};
use IO::Socket::INET ();

use constant DEFAULT_PORT => 7002;

use fields qw( name sockets pid client hooks );

### (CONSTRUCTOR) METHOD: new( $client, $name, @socket_names )
### Create a new lock object that corresponds to the specified I<name> and is
### held by the given I<sockets>.
sub new {
    my DDLock $self = shift;
    $self = fields::new($self) unless ref $self;

    $self->{client}  = shift;
    $self->{name}    = shift;
    $self->{pid}     = $$;
    $self->{sockets} = $self->getlocks(@_);
    $self->{hooks}   = {};                    # hookname -> coderef
    return $self;
}

### (PROTECTED) METHOD: getlocks( @servers )
### Try to obtain locks with the specified I<lockname> from one or more of the
### given I<servers>.
sub getlocks {
    my DDLock $self = shift;
    my $lockname    = $self->{name};
    my @servers     = @_;

    my @addrs = ();

    my $fail = sub {
        my $msg = shift;

        # release any locks that we did get:
        foreach my $addr (@addrs) {
            my $sock = $self->{client}->get_sock($addr)
                or next;
            $sock->printf( "releaselock lock=%s%s", eurl( $self->{name} ), CRLF );
            warn scalar(<$sock>);
        }
        die $msg;
    };

    # First create connected sockets to all the lock hosts
SERVER: foreach my $server (@servers) {
        my ( $host, $port ) = split /:/, $server;
        $port ||= DEFAULT_PORT;
        my $addr = "$host:$port";

        my $sock = $self->{client}->get_sock($addr)
            or next SERVER;

        $sock->printf( "trylock lock=%s%s", eurl($lockname), CRLF );
        chomp( my $res = <$sock> );
        $fail->("$server: '$lockname' $res\n") unless $res =~ m{^ok\b}i;

        push @addrs, $addr;
    }

    die "No available lock hosts" unless @addrs;
    return \@addrs;
}

sub name {
    my DDLock $self = shift;
    return $self->{name};
}

sub set_hook {
    my DDLock $self = shift;
    my $hookname = shift || return;

    if (@_) {
        $self->{hooks}->{$hookname} = shift;
    }
    else {
        delete $self->{hooks}->{$hookname};
    }
}

sub run_hook {
    my DDLock $self = shift;
    my $hookname = shift || return;

    if ( my $hook = $self->{hooks}->{$hookname} ) {
        local $@;
        eval { $hook->($self) };
        warn "DDLock hook '$hookname' threw error: $@" if $@;
    }
}

sub DESTROY {
    my DDLock $self = shift;

    $self->run_hook('DESTROY');
    local $@;
    eval { $self->_release_lock(@_) };

    return;
}

### METHOD: release()
### Release the lock held by the lock object. Returns the number of sockets that
### were released on success, and dies with an error on failure.
sub release {
    my DDLock $self = shift;

    $self->run_hook('release');
    return $self->_release_lock(@_);
}

sub _release_lock {
    my DDLock $self = shift;

    my $count = 0;

    my $sockets = $self->{sockets} or return;

    # lock server might have gone away, but we don't really care.
    local $SIG{'PIPE'} = "IGNORE";

    foreach my $addr (@$sockets) {
        my $sock = $self->{client}->get_sock_onlycache($addr)
            or next;

        my $res;

        eval {
            $sock->printf( "releaselock lock=%s%s", eurl( $self->{name} ), CRLF );
            $res = <$sock>;
            chomp $res;
        };

        if ( $res && $res !~ m/ok\b/i ) {
            my $port = $sock->peerport;
            my $addr = $sock->peerhost;
            die "releaselock ($addr): $res\n";
        }

        $count++;
    }

    return $count;
}

### FUNCTION: eurl( $arg )
### URL-encode the given I<arg> and return it.
sub eurl {
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_,.\\: -])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

#####################################################################
###     D D F I L E L O C K   C L A S S
#####################################################################
package DDFileLock;

BEGIN {
    use Fcntl qw{:DEFAULT :flock};
    use File::Spec qw{};
    use File::Path qw{mkpath};
    use IO::File qw{};

    use fields qw{name path tmpfile pid hooks};
}

our $TmpDir = File::Spec->tmpdir;

### (CONSTRUCTOR) METHOD: new( $lockname )
### Createa a new file-based lock with the specified I<lockname>.
sub new {
    my DDFileLock $self = shift;
    $self = fields::new($self) unless ref $self;
    my ( $name, $lockdir ) = @_;

    $self->{pid} = $$;

    $lockdir ||= $TmpDir;
    if ( !-d $lockdir ) {

        # Croaks if it fails, so no need for error-checking
        mkpath $lockdir;
    }

    my $lockfile = File::Spec->catfile( $lockdir, eurl($name) );

    # First open a temp file
    my $tmpfile = "$lockfile.$$.tmp";
    if ( -e $tmpfile ) {
        unlink $tmpfile or die "unlink: $tmpfile: $!";
    }

    my $fh = new IO::File $tmpfile, O_WRONLY | O_CREAT | O_EXCL
        or die "open: $tmpfile: $!";
    $fh->close;
    undef $fh;

    # Now try to make a hard link to it
    link( $tmpfile, $lockfile )
        or die "link: $tmpfile -> $lockfile: $!";
    unlink $tmpfile or die "unlink: $tmpfile: $!";

    $self->{path}    = $lockfile;
    $self->{tmpfile} = $tmpfile;
    $self->{hooks}   = {};

    return $self;
}

sub name {
    my DDFileLock $self = shift;
    return $self->{name};
}

sub set_hook {
    my DDFileLock $self = shift;
    my $hookname = shift || return;

    if (@_) {
        $self->{hooks}->{$hookname} = shift;
    }
    else {
        delete $self->{hooks}->{$hookname};
    }
}

sub run_hook {
    my DDFileLock $self = shift;
    my $hookname = shift || return;

    if ( my $hook = $self->{hooks}->{$hookname} ) {
        local $@;
        eval { $hook->($self) };
        warn "DDFileLock hook '$hookname' threw error: $@" if $@;
    }
}

### METHOD: release()
### Release the lock held by the object.
sub release {
    my DDFileLock $self = shift;
    $self->run_hook('release');
    return unless $self->{path};
    unlink $self->{path} or die "unlink: $self->{path}: $!";
    unlink $self->{tmpfile};
}

### FUNCTION: eurl( $arg )
### URL-encode the given I<arg> and return it.
sub eurl {
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_,.\\: -])/sprintf("%%%02X",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

DESTROY {
    my $self = shift;
    $self->run_hook('DESTROY');
    $self->release if $$ == $self->{pid};
}

#####################################################################
###     D D L O C K C L I E N T   C L A S S
#####################################################################
package DDLockClient;
use strict;
use Socket;

BEGIN {
    use fields qw( servers lockdir sockcache hooks );
    use vars qw{$Error};
}

$Error = undef;

our $Debug = 0;

sub get_sock_onlycache {
    my ( $self, $addr ) = @_;
    return $self->{sockcache}{$addr};
}

sub get_sock {
    my ( $self, $addr ) = @_;
    my $sock = $self->{sockcache}{$addr};
    return $sock if $sock && getpeername($sock);

    # TODO: cache unavailability for 'n' seconds?
    return $self->{sockcache}{$addr} = IO::Socket::INET->new(
        PeerAddr  => $addr,
        Proto     => "tcp",
        Type      => SOCK_STREAM,
        ReuseAddr => 1,
        Blocking  => 1,
    );
}

### (CLASS) METHOD: DebugLevel( $level )
sub DebugLevel {
    my $class = shift;

    if (@_) {
        $Debug = shift;
        if ($Debug) {
            *DebugMsg = *RealDebugMsg;
        }
        else {
            *DebugMsg = sub { };
        }
    }

    return $Debug;
}

sub DebugMsg { }

### (CLASS) METHOD: DebugMsg( $level, $format, @args )
### Output a debugging messages formed sprintf-style with I<format> and I<args>
### if I<level> is greater than or equal to the current debugging level.
sub RealDebugMsg {
    my ( $class, $level, $fmt, @args ) = @_;
    return unless $Debug >= $level;

    chomp $fmt;
    printf STDERR ">>> $fmt\n", @args;
}

### (CONSTRUCTOR) METHOD: new( %args )
### Create a new DDLockClient
sub new {
    my DDLockClient $self = shift;
    my %args = @_;

    $self = fields::new($self) unless ref $self;
    die "Servers argument must be an arrayref if specified"
        unless !exists $args{servers} || ref $args{servers} eq 'ARRAY';
    $self->{servers} = $args{servers} || [];
    $self->{lockdir} = $args{lockdir} || '';
    $self->{sockcache} = {};    # "host:port" -> IO::Socket::INET
    $self->{hooks}     = {};    # hookname -> coderef

    return $self;
}

sub set_hook {
    my DDLockClient $self = shift;
    my $hookname = shift || return;

    if (@_) {
        $self->{hooks}->{$hookname} = shift;
    }
    else {
        delete $self->{hooks}->{$hookname};
    }
}

sub run_hook {
    my DDLockClient $self = shift;
    my $hookname = shift || return;

    if ( my $hook = $self->{hooks}->{$hookname} ) {
        local $@;
        eval { $hook->($self) };
        warn "DDLockClient hook '$hookname' threw error: $@" if $@;
    }
}

### METHOD: trylock( $name )
### Try to get a lock from the lock daemons with the specified I<name>. Returns
### a DDLock object on success, and undef on failure.
sub trylock {
    my DDLockClient $self = shift;
    my $lockname = shift;

    $self->run_hook( 'trylock', $lockname );

    my $lock;
    local $@;

    # If there are servers to connect to, use a network lock
    if ( @{ $self->{servers} } ) {
        $self->DebugMsg( 2, "Creating a new DDLock object." );
        $lock = eval { DDLock->new( $self, $lockname, @{ $self->{servers} } ) };
    }

    # Otherwise use a file lock
    else {
        $self->DebugMsg( 2, "No servers configured: Creating a new DDFileLock object." );
        $lock = eval { DDFileLock->new( $lockname, $self->{lockdir} ) };
    }

    # If no lock was acquired, fail and put the reason in $Error.
    unless ($lock) {
        my $eval_error = $@;
        $self->run_hook('trylock_failure');
        return $self->lock_fail($eval_error) if $eval_error;
        return $self->lock_fail("Unknown failure.");
    }

    $self->run_hook( 'trylock_success', $lockname, $lock );

    return $lock;
}

### (PROTECTED) METHOD: lock_fail( $msg )
### Set C<$!> to the specified message and return undef.
sub lock_fail {
    my DDLockClient $self = shift;
    my $msg = shift;

    $Error = $msg;
    return undef;
}

1;

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
