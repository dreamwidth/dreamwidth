#!/usr/bin/perl
#
# DW::Controller::Dev
#
# This controller is for tiny pages related to dev work
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Dev;

use strict;
use warnings;
use DW::Routing;

DW::Routing->register_static( '/dev/classes', 'dev/classes.tt', app => 1 );

1;
