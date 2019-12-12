#!/bin/bash

set -xe

# Validate that the system is set up and working correctly. If this fails, sleep forever
# so that someone can log in and debug.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || sleep infinity

# Run whatever was passed as an argument.
COMMAND="$1"
shift

while true; do
    # If the worker exits successfully, run it again -- it was probably just done
    # running jobs and freeing up memory. Any other condition, propogate.
    $LJHOME/$COMMAND "$@" || exit $?
done
