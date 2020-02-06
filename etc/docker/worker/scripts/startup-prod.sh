#!/bin/bash

set -xe

fail () {
    echo "-- failure detected --"
    sleep 30
    exit 1
}

# Validate that the system is set up and working correctly. If this fails, give it 30 seconds
# so operators can view the logs, then exit.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || fail

# Run whatever was passed as an argument.
COMMAND="$1"
shift

while true; do
    # If the worker exits successfully, run it again -- it was probably just done
    # running jobs and freeing up memory. Any other condition, propogate.
    $LJHOME/$COMMAND "$@" || exit $?
done
