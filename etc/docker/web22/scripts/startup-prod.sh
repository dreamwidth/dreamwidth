#!/bin/bash

set -xe

# Validate that the system is set up and working correctly. If this fails, sleep forever
# so that someone can log in and debug.
perl -I$LJHOME/extlib/ $LJHOME/bin/checkconfig.pl || sleep infinity

# Starman on port 8080
mkdir -p /var/log/starman

# Worker count. Do NOT derive this from nproc: on Fargate nproc reports 2 even
# for a 1-vCPU task, so nproc*8 spawned 16 workers and OOM-killed the 6GB task
# under load. Use an explicit, memory-safe default (10 fits 6GB; --preload-app
# adds headroom) that can be overridden per service via DW_STARMAN_WORKERS.
WORKERS=${DW_STARMAN_WORKERS:-10}

# Recycle each worker after this many requests to cap memory growth. Starman's
# built-in default is 1000, which is too high for the 6GB budget under logged-in
# load (workers climb to ~600MB before cycling). Low QPS here, so frequent
# recycling is cheap — especially with --preload-app (respawn = fork, no recompile).
MAX_REQUESTS=${DW_STARMAN_MAX_REQUESTS:-100}

# --disable-keepalive: prefork workers pin to idle keep-alive conns behind the pooling ALB.
perl $LJHOME/bin/starman --port 8080 --workers "$WORKERS" --max-requests "$MAX_REQUESTS" --disable-keepalive --preload-app --log /var/log/starman --daemonize

# Sleep a few seconds to ensure things get up and running
sleep 5

# Now we "wait" by tailing the error log, so we can see it without having
# to attach to the container
tail -F /var/log/starman/error.log
