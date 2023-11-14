#!/bin/bash

set -xe

# Start proxy into background somewhere
/dw/src/proxy/proxy \
    -port 6250 \
    -salt_file=/dw/etc/proxy-salt \
    -hotlink_domain=dreamwidth.org \
    -cache_dir=/dw/var/proxy

# Now we "wait" by tailing the error log, so we can see it without having
# to attach to the container
tail -F /var/log/apache2/error.log
