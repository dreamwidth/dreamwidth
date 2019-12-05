#!/bin/bash

set -xe

# Validate that the system is set up and working correctly.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl

# do something forever
sleep infinity
