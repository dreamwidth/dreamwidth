# mogstored device monitoring plugin.  this fetches the 'usage' file from a device
# and parses it, putting the information in the server.
#
# written by Mark Smith <junior@danga.com>

package MogstoredPlugin;

# packages we need
use LWP::Simple;
use Time::HiRes qw(gettimeofday tv_interval);

# called when we're loaded.  here we can do anything necessary to set ourselves
# up if we want.
sub register {
    debug("mogstored plugin registered");
    return 1;
}

# this is called and given the job name as the first parameter and an array ref of
# options passed in as the second parameter.
sub worker {
    my ($job, $options) = @_;
    my $url = shift(@{$options || []});
    my $interval = shift(@{$options || []}) || 60;
    return unless $url;

    # get stats every $interval seconds
    while (1) {
        my $t0 = [ gettimeofday ];
        my $doc = get($url);
        my $time = tv_interval($t0);
        unless (defined $doc) {
            set("$job.status", "fetch_failure");
            sleep $interval;
            next;
        }

        # split the doc and parse
        my %stats;
        foreach (split(/\r?\n/, $doc)) {
            next unless /^(\w+):\s+(.+)$/;
            my ($key, $val) = ($1, $2);
            $stats{$key} = $val;
        }

        # if we couldn't parse it
        unless ($stats{time} && $stats{total} && $stats{used} && $stats{available}) {
            set("$job.status", "parse_failure");
            sleep $interval;
            next;
        }

        # mark this as successfully retrieved
        set("$job.status", "success");
        set("$job.time", $stats{time});
        set("$job.used", $stats{used});
        set("$job.available", $stats{available});
        set("$job.total", $stats{total});
        set("$job.delay", sprintf("%5.3f", $time));

        # sleep a good 60 seconds, as this file doesn't change very often
        sleep $interval;
    }
}

# calls the registrar in the main program, giving them information about us.  this
# has to be called as main:: or just ::register_plugin because we're in our own
# package and we want to talk to the register function in the main namespace.
main::register_plugin('mogstored', 'MogstoredPlugin', {
    register => \&register,
    worker => \&worker,
});

1;
