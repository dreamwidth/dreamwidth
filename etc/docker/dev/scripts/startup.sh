#!/bin/bash

set -xe

# Validate that the system is set up and working correctly.
prove -I$LJHOME/extlib/ $LJHOME/t/01-dw.t

# do something forever
sleep infinity
