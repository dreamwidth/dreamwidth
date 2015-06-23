# t/01-dw.t
#
# Test to make sure the DW->home directory exists
#
# Authors:
#      Ricky Buchanan <ricky@notdoneliving.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;

use Test::More tests => 3;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }

use_ok('DW');

my $dir = DW->home;

ok($dir, 'DW->home returns something');
ok(-d $dir, 'DW->home returns a directory');

