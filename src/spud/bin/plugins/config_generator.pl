# automatic monitoring config generator plugin for LiveJournal.  to use, add a
# line like this to your SPUD config:
#
# config_generator(mysql, perlbal, memcached, mogstored, mogilefsd)
#
# written by Mark Smith <junior@danga.com>

package ConfigGenPlugin;

use strict;

# called when we're loaded.  here we can do anything necessary to set ourselves
# up if we want.  in this case we just load the LJ libraries.
sub register {
    # load up our livejournal files
    use lib "$ENV{LJHOME}/cgi-bin";
    require 'ljlib.pl';

    # signal success if we get here
    return 1;
}

# this is called and given the job name as the first parameter and an array ref of
# options passed in as the second parameter.
sub helper {
    my $options = shift;

    # put options into hashref for easy use later
    my %opts;
    foreach my $opt (@$options) {
        my @parms = split(/\s*=\s*/, $opt);
        my $job = shift(@parms);
        $opts{$job} = \@parms;
    }

    # this is the main loop
    LJ::start_request();

    # mark all of our jobs as being inactive so that if we don't readd them below
    # they'll get reaped automatically.
    mark_inactive_by_plugin('config_generator');

    # look for any perlbals that need monitoring jobs
    if ($opts{perlbal}) {
        while (my ($srvr, $ipaddr) = each %LJ::PERLBAL_SERVERS) {
            add_job("perlbal.$srvr", "perlbal", [ $ipaddr, @{$opts{perlbal}} ], 'config_generator');
        }
    }

    # and now memcache servers
    if ($opts{memcached}) {
        foreach my $host (@LJ::MEMCACHE_SERVERS) {
            my $ipaddr = ref $host ? $host->[0] : $host;
            add_job("memcached.$ipaddr", "memcached", [ $ipaddr, @{$opts{memcached}} ], 'config_generator');
        }
    }

    # mogilefsd
    if ($opts{mogilefsd} && %LJ::MOGILEFS_CONFIG) {
        foreach my $ipaddr (@{$LJ::MOGILEFS_CONFIG{hosts}}) {
            add_job("mogilefsd.$ipaddr", "mogilefsd", [ $ipaddr, @{$opts{mogilefsd}} ], 'config_generator');
        }
    }

    # mogstored
    if ($opts{mogstored} && %LJ::MOGILEFS_CONFIG) {
        my $mgd = new MogileFS::Admin(hosts => $LJ::MOGILEFS_CONFIG{hosts});
        if ($mgd) {
            my (%hosthash, %devhash);

            if (my $hosts = $mgd->get_hosts) {
                foreach my $h (@$hosts) {
                    $hosthash{$h->{hostid}} = $h;
                }
            }

            if (my $devs = $mgd->get_devices) {
                foreach my $d (@$devs) {
                    $devhash{$d->{devid}} = $d;
                }
            }

            foreach my $devid (keys %devhash) {
                my $host = $hosthash{$devhash{$devid}->{hostid}};
                add_job("mogstored.dev$devid", "mogstored",
                        [ "http://$host->{hostip}:$host->{http_port}/dev$devid/usage", @{$opts{mogstored}} ],
                        'config_generator');
            }

            foreach my $host (values %hosthash) {
                my $ipaddr = "$host->{hostip}:7501";
                add_job("mogstored.$ipaddr", "perlbal", [ $ipaddr, @{$opts{perlbal} || []} ], 'config_generator');
            }
        }
    }

    if ($opts{mysql} || $opts{db} || $opts{database}) {
        
    }

    # done, call end request and sleep for a while
    LJ::end_request();
}

# calls the registrar in the main program, giving them information about us.  this
# has to be called as main:: or just ::register_plugin because we're in our own
# package and we want to talk to the register function in the main namespace.
main::register_plugin('config_generator', 'ConfigGenPlugin', {
    register => \&register,
    helper => \&helper,
});

1;
