#!/bin/bash
#
# Designed to be run as part of the Docker setup. Do not run this
# script manually.
#

set -xe

service mysql start

$LJHOME/t/bin/initialize-db
