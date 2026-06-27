#!/bin/bash
#
# Designed to be run as part of the Docker setup. Do not run this
# script manually.
#

# Set up Varnish.
rm -rf /etc/varnish/default.vcl
ln -s /dw/ext/local/etc/varnish/dreamwidth.vcl /etc/varnish/default.vcl
