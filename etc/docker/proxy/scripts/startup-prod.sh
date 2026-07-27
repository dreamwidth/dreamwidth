#!/bin/bash

set -xe

# Run the proxy in the foreground. It blocks on http.ListenAndServe and logs to
# stderr (captured by Docker), so it is the container's long-running main process.
/dw/src/proxy/proxy \
    -port 6250 \
    -salt_file=/dw/etc/proxy-salt \
    -hotlink_domain=dreamwidth.org \
    -cache_dir=/dw/var/proxy
