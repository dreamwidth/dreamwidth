#!/bin/bash
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
# Dispatcher: detects available tools and delegates to the appropriate
# build-static implementation.

release=$(cat /etc/lsb-release 2>/dev/null)
if echo "$release" | grep -q '18.04'; then
    exec "$LJHOME/bin/build-static-legacy.sh" "$@"
else
    exec "$LJHOME/bin/build-static-modern.sh" "$@"
fi
