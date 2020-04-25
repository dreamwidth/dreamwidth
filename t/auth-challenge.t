# t/blobstore.t
#
# Test some DW::Auth::Challenge functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

plan tests => 8;

use DW::Auth::Challenge;

# Test generation
my $chal  = DW::Auth::Challenge->generate;
my @parts = split( /:/, $chal );
ok( $parts[0] eq 'c0',                                       'Challenge v0.' );
ok( $parts[1] == ( time() - time() % 3600 ),                 'Challenge on hourly boundary.' );
ok( $parts[3] == 60,                                         'Challenge for 60 seconds.' );
ok( $parts[4] =~ /^[a-zA-Z0-9]+$/,                           'Challenge is alphanumeric.' );
ok( DW::Auth::Challenge->get_attributes($chal) eq $parts[4], 'Challenge attributes.' );

# Check validition of valid
ok( DW::Auth::Challenge->check($chal), 'Challenge is valid.' );

# Invalid challenge fails
ok( !DW::Auth::Challenge->check( $chal . '?' ), 'Challenge not valid.' );

# Can't extend challenge
$parts[3] = 70;
ok( !DW::Auth::Challenge->check( join( ':', @parts ) ), 'Challenge cannot be extended.' );

1;
