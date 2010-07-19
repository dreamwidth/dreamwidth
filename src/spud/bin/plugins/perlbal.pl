# perlbal monitoring plugin.  very simple right now, this gets the output of the states
# command and saves it to spud.  this is also used on the mogstored sidechannel, which
# is a perlbal management interface.
# 
# written by Mark Smith <junior@danga.com>

package PerlbalPlugin;

use strict;

# called when we're loaded.  here we can do anything necessary to set ourselves
# up if we want.
sub register {
    debug("perlbal plugin registered");
    return 1;
}

# this is called and given the job name as the first parameter and an array ref of
# options passed in as the second parameter.
sub worker {
    my ($job, $options) = @_;
    my $ipaddr = shift(@{$options || []});
    my $interval = shift(@{$options || []}) || 5;
    return unless $ipaddr;

    # try to get states every second
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
        print $sock "states\r\n";
        my $out = $read_input->();
        foreach my $line (@$out) {
            if ($line =~ /^(.+?)\s+(\w+)\s+(\d+)$/) {
                my ($class, $state, $count) = ($1, $2, $3);
                $class =~ s/^(.+::)//;
                set("$job.$class.$state", $count);
            }
        }

        # now sleep some between doing things
        sleep $interval;
    }
}

# calls the registrar in the main program, giving them information about us.  this
# has to be called as main:: or just ::register_plugin because we're in our own
# package and we want to talk to the register function in the main namespace.
main::register_plugin('perlbal', 'PerlbalPlugin', {
    register => \&register,
    worker => \&worker,
});

1;
