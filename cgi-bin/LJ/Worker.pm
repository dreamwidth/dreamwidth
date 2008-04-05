package LJ::Worker;

use IO::Socket::UNIX ();
use POSIX ();

use strict;


# this will force preloading (rather than lazy) or all
# modules so they're loaded in shared memory before the
# fork (mod_perl-style)
use Class::Autouse qw{:devel};

BEGIN {
    my $debug = $ENV{DEBUG} ? 1 : 0;
    eval "sub DEBUG () { $debug }";
}

my $mother_sock_path;

##############################
# Child and forking management

my $fork_count = 0;

my $original_name = $0;

sub setup_mother {
    my $class = shift;

    # Curerntly workers use a SIGTERM handler to prevent shutdowns in the middle of operations,
    # we need TERM to apply right now in this code
    local $SIG{TERM};
    local $SIG{CHLD} = "IGNORE";
    local $SIG{PIPE} = "IGNORE";

    return unless $ENV{SETUP_MOTHER};
    my ($function) = $0 =~ m{([^/]+)$};
    my $sock_path = "/var/run/workers/$function.sock";

    warn "Checking for existing mother at $sock_path" if DEBUG;

    if (my $sock = IO::Socket::UNIX->new(Peer => $sock_path)) {
        warn "Asking other mother to stand down. We're in charge now" if DEBUG;
        print $sock "SHUTDOWN\n";
    } else {
        warn "Other mother didn't exist: $!";
    }

    unlink $sock_path; # No error trap, the file may not exist
    my $listener = IO::Socket::UNIX->new(Local => $sock_path, Listen => 1);

    die "Error creating listening unix socket at '$sock_path': $!" unless $listener;

    warn "Waiting for input" if DEBUG;
    local $0 = "$original_name [mother]";
    $mother_sock_path = $sock_path;
    while (accept(my $sock, $listener)) {
        $sock->autoflush(1);
        while (my $input = <$sock>) {
            chomp $input;

            my $method = "MANAGE_" . lc($input);
            if (my $cv = $class->can($method)) {
                warn "Executing '$method' function" if DEBUG;
                my $rv = $cv->($class);
                return unless $rv; #return value of command handlers determines if the loop stays running.
                print $sock "OK $rv\n";
            } else {
                print $sock "ERROR unknown command\n";
            }
        }
    }
}

sub MANAGE_shutdown {
    exit;
}

sub MANAGE_fork {
    my $pid = fork();

    unless (defined $pid) {
        warn "Couldn't fork: $!";
        return 1; # continue running the management loop if we can't fork
    }

    if ($pid) {
        $fork_count++;
        $0 = "$original_name [mother] $fork_count";
        # Return the pid, true value to continue the loop, pid for webnoded to track children.
        return $pid;
    }

    POSIX::setsid();
    $SIG{HUP} = 'IGNORE';

    ## Close open file descriptors
    close(STDIN);
    close(STDOUT);
    close(STDERR);

    ## Reopen stderr, stdout, stdin to /dev/null
    open(STDIN,  "+>/dev/null");
    open(STDOUT, "+>&STDIN");
    open(STDERR, "+>&STDIN");

    return 0; # we're a child process, the management loop should cleanup and end because we want to start up the main worker loop.
}

##########################
# Memory consuption checks

use GTop ();
my $gtop = GTop->new;
my $last_mem_check = 0;

my $memory_limit;

sub set_memory_limit {
    my $class = shift;
    $memory_limit = shift;
}

sub check_limits {
    return unless defined $memory_limit;
    my $now = int time();
    return if $now == $last_mem_check;
    $last_mem_check = $now;

    my $proc_mem = $gtop->proc_mem($$);
    my $rss = $proc_mem->rss;
    return if $rss < $memory_limit;

    if ($mother_sock_path and my $sock = IO::Socket::UNIX->new(Peer => $mother_sock_path)) {
        print $sock "FORK\n";
        close $sock;
    } else {
        warn "Unable to contact mother process at $mother_sock_path";
    }
    die "Exceeded maximum ram usage: $rss greater than $memory_limit";
}

1;
