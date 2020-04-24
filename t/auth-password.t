# t/blobstore.t
#
# Test some DW::Auth::Password functionality.
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

plan tests => 9;

use DW::Auth::Password;
use LJ::Test qw/ temp_user /;

my $u = temp_user();

# Test public APIs work
ok( $u->dversion == 10,           'New user is on dversion 10.' );
ok( $u->set_password('test'),     'Able to set password.' );
ok( $u->check_password('test'),   'Password validates.' );
ok( !$u->check_password('test?'), 'Password fails validation.' );

# Looks like a bcrypt hash (not quite base64)
my $hash1 = DW::Auth::Password->_password_hash($u);
ok( $hash1 =~ m!^\$2a\$$LJ::BCRYPT_COST\$[a-zA-Z0-9./]+$!, 'Appropriate bcrypt hash.' );

# Same password results in different hash
ok( $u->set_password('test'),                         'Able to set password.' );
ok( $hash1 ne DW::Auth::Password->_password_hash($u), 'Same password uses new hash.' );
ok( $u->check_password('test'),                       'Password validates.' );
ok( !$u->check_password('test?'),                     'Password fails validation.' );

1;
