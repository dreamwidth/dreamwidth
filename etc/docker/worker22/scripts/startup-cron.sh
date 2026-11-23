#!/bin/bash

# Entry point for scheduled (EventBridge -> ECS RunTask) cron tasks.
#
# Unlike startup-prod.sh, which loops forever to keep a resident queue worker
# running, a scheduled task must run its command exactly once and exit so the
# next scheduled run starts a fresh task. We validate config first, then run the
# command so its exit code becomes the task's (a non-zero exit is what the
# task-failure alarm keys on). Overlap between runs is guarded in the app layer
# (e.g. ljmaint via DW::Locker's global GET_LOCK), not here.
#
# Commands may be chained with "--". A task's filesystem is ephemeral, so a job
# that produces artifacts and a job that ships them elsewhere have to run in the
# same task to see the same disk (e.g. genstats then archive-to-s3.pl). set -e
# aborts the chain at the first failure, and that command's status is the task's.

set -xe

fail () {
    echo "-- failure detected --"
    sleep 30
    exit 1
}

perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || fail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <command-relative-to-LJHOME> [args...] [-- <command> [args...]]..." >&2
    exit 2
fi

GROUP=()

run_group () {
    if [[ ${#GROUP[@]} -eq 0 ]]; then
        echo "Empty command in chain" >&2
        exit 2
    fi
    "$LJHOME/${GROUP[0]}" "${GROUP[@]:1}"
    GROUP=()
}

for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
        run_group
    else
        GROUP+=("$arg")
    fi
done

run_group
