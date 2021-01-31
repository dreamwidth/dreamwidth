#!/bin/bash

set -e

echo "Dreamwidth dev container initializing..."

echo -n "Starting mysql..."
service mysql start &>/dev/null
echo "done!"

# Validate that the system is set up and working correctly.
echo -n "Preflight test..."
prove -I$LJHOME/extlib/ $LJHOME/t/01-dw.t &>/dev/null
echo "done!"

# drop to shell, have fun
cd $LJHOME

echo
echo "Welcome to the Dreamwidth development container!"
echo
echo "This is meant to be an easy way to develop and run tests, but is not really a"
echo "full fledged web server. I.e., great for doing backend work, maybe less than"
echo "great for doing frontend work right now."
echo

HOME=/dw bash
