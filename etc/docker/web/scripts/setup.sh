#!/bin/bash
#
# Designed to be run as part of the Docker setup. Do not run this
# script manually.
#

# Set up Apache2.
rm -rf /etc/apache2
ln -s /dw/ext/local/etc/apache2 /etc/apache2

# Set up Varnish.
rm -rf /etc/varnish/default.vcl
ln -s /dw/ext/local/etc/varnish/dreamwidth.vcl /etc/varnish/default.vcl
