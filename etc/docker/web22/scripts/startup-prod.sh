#!/bin/bash

set -xe

# Validate that the system is set up and working correctly. If this fails, sleep forever
# so that someone can log in and debug.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || sleep infinity

# Starman on port 8080 (Varnish sits in front on 6081)
mkdir -p /var/log/starman
perl $LJHOME/bin/starman --port 8080 --workers 10 --log /var/log/starman --daemonize

# Kick off Varnish
service varnish start

# Sleep a few seconds to ensure things get up and running
sleep 5

# Now we "wait" by tailing the error log, so we can see it without having
# to attach to the container
tail -F /var/log/starman/error.log
