#!/bin/bash

set -xe

# Validate that the system is set up and working correctly. If this fails, sleep forever
# so that someone can log in and debug.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || sleep infinity

# Run whatever was passed as an argument.
COMMAND="$1"
shift
$LJHOME/$COMMAND "$@" || sleep infinity
