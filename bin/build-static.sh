#!/bin/bash
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
# Dispatcher: detects available tools and delegates to the appropriate
# build-static implementation.

if command -v sass >/dev/null 2>&1; then
    exec "$LJHOME/bin/build-static-modern.sh" "$@"
elif command -v compass >/dev/null 2>&1; then
    exec "$LJHOME/bin/build-static-legacy.sh" "$@"
else
    echo "Error: neither sass nor compass found in PATH" >&2
    exit 1
fi
