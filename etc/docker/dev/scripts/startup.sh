#!/bin/bash

set -xe

# Validate that the system is set up and working correctly.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl

# Varnish us
service varnish start

# Kick off Apache
/usr/sbin/apache2ctl configtest
/usr/sbin/apache2ctl -DFOREGROUND
