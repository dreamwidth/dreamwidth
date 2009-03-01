# memcache monitoring plugin for SPUD.  this is a simple plugin that gets stats
# information from memcache and sticks it in the server.
#
# written by Mark Smith <junior@danga.com>

package MemcachedPlugin;

use strict;

# called when we're loaded.  here we can do anything necessary to set ourselves
# up if we want.
sub register {
    debug("memcached plugin registered");
    return 1;
}

# this is called and given the job name as the first parameter and an array ref of
# options passed in as the second parameter.
sub worker {
    my ($job, $options) = @_;
    my $ipaddr = shift(@{$options || []});
    my $interval = shift(@{$options || []}) || 5;
    return unless $ipaddr;

    # loop and get statistics every second
    my $sock;
    my $read_input = sub {
        my @out;
        while (<$sock>) {
            s/[\r\n\s]+$//;
            last if /^END/;
            push @out, $_;
        }
        return \@out;
    };
    while (1) {
        $sock ||= IO::Socket::INET->new(PeerAddr => $ipaddr, Timeout => 3);
        return unless $sock;

        # basic states command
        print $sock "stats\r\n";
        my $out = $read_input->();
        foreach my $line (@$out) {
            if ($line =~ /^STAT\s+([\w:]+)\s+(.+)$/) {
                my ($stat, $val) = ($1, $2);
                set("$job.$stat", $val);
            }
        }

        # now sleep some between doing things
        sleep $interval;
    }
}

# calls the registrar in the main program, giving them information about us.  this
# has to be called as main:: or just ::register_plugin because we're in our own
# package and we want to talk to the register function in the main namespace.
main::register_plugin('memcached', 'MemcachedPlugin', {
    register => \&register,
    worker => \&worker,
});

1;
