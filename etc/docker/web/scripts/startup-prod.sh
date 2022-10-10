#!/bin/bash

set -xe

# Validate that the system is set up and working correctly. If this fails, sleep forever
# so that someone can log in and debug.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || sleep infinity

# Kick off Apache
mkdir $LJHOME/ext/local/etc/apache2/sites-enabled || true
cp $LJHOME/ext/local/dreamwidth-prod.conf $LJHOME/ext/local/etc/apache2/sites-enabled/dreamwidth.conf
/usr/sbin/apache2ctl start

# Kick off Varnish
service varnish start

# Sleep a few seconds to ensure things get up and running
sleep 5

# Now we "wait" by tailing the error log, so we can see it without having
# to attach to the container
tail -F /var/log/apache2/error.log
