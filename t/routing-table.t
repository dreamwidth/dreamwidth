# t/routing-table.t
#
# Test to make sure the routing table is non-empty
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

require $LJ::HOME . "/t/bin/routing-table-helper.pl";
