# t/blobstore.t
#
# Test some DW::Auth::TOTP functionality.
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

plan tests => 22;

use DW::Auth::Password;
use DW::Auth::TOTP;
use LJ::Test qw/ temp_user /;

my $u = temp_user();

# Test public APIs work
ok( !DW::Auth::TOTP->is_enabled($u), 'New user does not have TOTP.' );
ok( scalar( DW::Auth::TOTP->get_recovery_codes($u) ) == 0,
    'New user does not have recovery codes.' );

# Enable
my $secret = DW::Auth::TOTP->generate_secret;
ok( DW::Auth::TOTP->enable( $u, $secret ), 'Enable works.' );
ok( DW::Auth::TOTP->is_enabled($u),                         'User has TOTP now.' );
ok( scalar( DW::Auth::TOTP->get_recovery_codes($u) ) == 10, 'User has 10 codes.' );

# Get some codes and check validation
my @codes = DW::Auth::TOTP->_get_codes($u);
ok( scalar @codes == 2, 'Got 2 codes.' );
ok( DW::Auth::TOTP->check_code( $u, $codes[0] ), 'Older code works.' );
ok( DW::Auth::TOTP->check_code( $u, $codes[0] ), 'Newer code works.' );
ok( !DW::Auth::TOTP->check_code( $u, '000000' ), 'Bad code fails.' );

# Recovery code tests
my @recovery = DW::Auth::TOTP->get_recovery_codes($u);
is( scalar @recovery, 10, 'User has 10 recovery codes.' );

my $rc = $recovery[0];
ok( DW::Auth::TOTP->check_recovery_code( $u, $rc ), 'Recovery code validates.' );
ok( !DW::Auth::TOTP->check_recovery_code( $u, $rc ), 'Same recovery code cannot be reused.' );

my @remaining = DW::Auth::TOTP->get_recovery_codes($u);
is( scalar @remaining, 9, 'One fewer recovery code after use.' );

ok( !DW::Auth::TOTP->check_recovery_code( $u, 'not-real' ), 'Invalid recovery code rejected.' );

# TODO: maybe we care, but there is _technicaly_ a race condition since we're
# using time based authentication, and we could just implement a way to set
# the time for tests, but I'm not yet (since adding functionality to set time
# in a TOTP system seems spooky)

# Disable
ok( DW::Auth::Password->set( $u, 'test' ), 'Changed user password.' );
ok( !DW::Auth::TOTP->disable( $u, 'fail' ), 'Fail to disable without password.' );
ok( DW::Auth::TOTP->disable( $u, 'test' ), 'Disable works.' );
ok( !DW::Auth::TOTP->is_enabled($u), 'Disabled user does not have TOTP.' );
ok(
    scalar( DW::Auth::TOTP->get_recovery_codes($u) ) == 0,
    'Disabled user does not have recovery codes.'
);

# Codes fail now
ok( !DW::Auth::TOTP->check_code( $u, $codes[0] ), 'Older code fails.' );
ok( !DW::Auth::TOTP->check_code( $u, $codes[0] ), 'Newer code fails.' );
ok( !DW::Auth::TOTP->check_code( $u, '000000' ),  'Bad code still fails.' );

1;
