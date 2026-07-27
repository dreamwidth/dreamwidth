#!/bin/bash

# Entry point for scheduled (EventBridge -> ECS RunTask) cron tasks.
#
# Unlike startup-prod.sh, which loops forever to keep a resident queue worker
# running, a scheduled task must run its command exactly once and exit so the
# next scheduled run starts a fresh task. We validate config first, then exec
# the command so its exit code becomes the task's (a non-zero exit is what the
# task-failure alarm keys on). Overlap between runs is guarded in the app layer
# (e.g. ljmaint via DW::Locker's global GET_LOCK), not here.

set -xe

fail () {
    echo "-- failure detected --"
    sleep 30
    exit 1
}

perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || fail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <command-relative-to-LJHOME> [args...]" >&2
    exit 2
fi

COMMAND="$1"
shift
exec "$LJHOME/$COMMAND" "$@"
