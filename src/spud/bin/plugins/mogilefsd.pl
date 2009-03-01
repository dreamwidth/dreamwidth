# mogilefsd monitoring plugin.  this looks at the stats which is a very quick
# operation for the mogilefsd server.  plans for this plugin are to start
# monitoring replication, recent queries, etc.
#
# written by Mark Smith <junior@danga.com>

package MogilefsdPlugin;

use strict;

# called when we're loaded.  here we can do anything necessary to set ourselves
# up if we want.
sub register {
    debug("mogilefsd plugin registered");
    return 1;
}

# this is called and given the job name as the first parameter and an array ref of
# options passed in as the second parameter.
sub worker {
    my ($job, $options) = @_;
    my $ipaddr = shift(@{$options || []});
    my $interval = shift(@{$options || []}) || 5;
    return unless $ipaddr;

    # test plugin simply loops and once a second sets a "heartbeat"
    my $sock;
    my $read_input = sub {
        my @out;
        while (<$sock>) {
            s/[\r\n\s]+$//;
            last if /^\./;
            push @out, $_;
        }
        return \@out;
    };
    while (1) {
        $sock ||= IO::Socket::INET->new(PeerAddr => $ipaddr, Timeout => 3);
        return unless $sock;

        # basic states command
        print $sock "!stats\r\n";
        my $out = $read_input->();
        foreach my $line (@$out) {
            if ($line =~ /^([\w:]+)\s+(.+)$/) {
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
main::register_plugin('mogilefsd', 'MogilefsdPlugin', {
    register => \&register,
    worker => \&worker,
});

1;
