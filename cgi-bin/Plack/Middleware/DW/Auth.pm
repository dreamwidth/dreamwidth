#!/usr/bin/perl
#
# Plack::Middleware::DW::Auth
#
# Plack middleware that supports authentication for the Dreamwidth system.
# Anything that is involved in determining if a user is authenticated or not,
# should go in this file (and likely call out to the core auth libraries.)
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2021 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::Auth;

use strict;
use v5.10;

