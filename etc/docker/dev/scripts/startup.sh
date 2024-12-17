#!/bin/bash

set -xe

# Services started
# service varnish start
service mysqld start

# Validate that the system is set up and working correctly.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl

# Kick off Apache
/usr/sbin/apache2ctl configtest
/usr/sbin/apache2ctl start

# Tail apache log, it's the most sensible
tail -f /var/log/apache2/error.log
