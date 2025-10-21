#!/bin/bash
#
# Designed to be run as part of the Docker setup. Do not run this
# script manually.
#

# Set up Apache2.
rm -rf /etc/apache2
ln -s /dw/ext/local/etc/apache2 /etc/apache2
