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

plan tests => 19;

use Digest::MD5 qw/ md5_hex /;

use DW::API::Key;
use DW::Auth::Password;
use LJ::Test qw/ temp_user /;

my $u = temp_user();

# Test public APIs work
ok( $u->dversion == 10, 'New user is on dversion 10.' );
ok( DW::Auth::Password->set( $u, 'test' ), 'Able to set password.' );
ok( DW::Auth::Password->check( $u, 'test' ), 'Password validates.' );
ok( !DW::Auth::Password->check( $u, 'test?' ), 'Password fails validation.' );

# Looks like a bcrypt hash (not quite base64)
my $hash1 = DW::Auth::Password->_get_password_token($u);
ok( $hash1 =~ m!^\$2a\$$LJ::BCRYPT_COST\$[a-zA-Z0-9./]+$!, 'Appropriate bcrypt hash.' );

# Same password results in different hash
ok( DW::Auth::Password->set( $u, 'test' ), 'Able to set password.' );
ok( $hash1 ne DW::Auth::Password->_get_password_token($u), 'Same password uses new hash.' );
ok( DW::Auth::Password->check( $u, 'test' ), 'Password validates.' );
ok( !DW::Auth::Password->check( $u, 'test?' ), 'Password fails validation.' );

# Now let's test some compatibility layers, let's give the user an API key
# and test that auth works
my $key = DW::API::Key->new_for_user($u);
ok( !DW::Auth::Password->check( $u, $key->hash ), 'API key is not valid without options.' );
ok( DW::Auth::Password->check( $u, $key->hash, allow_api_keys => 1 ),
    'API key is valid with options.' );

# And test that hpassword does not work for password
ok( !DW::Auth::Password->check( $u, md5_hex('test'), allow_hpassword => 1 ),
    'hpassword does not work for d10.' );
ok( !DW::Auth::Password->check( $u, md5_hex('test'), allow_hpassword => 1, allow_api_keys => 1 ),
    'hpassword does not work for d10 (w/API keys).' );

# And now it does (when we pass an API key hashed)
ok(
    DW::Auth::Password->check(
        $u, md5_hex( $key->hash ),
        allow_hpassword => 1,
        allow_api_keys  => 1
    ),
    'API key is valid with options w/hpassword.'
);

# Roll the user back to d9
$u->update_self( { dversion => 9 } );

# Test password flow again
ok( $u->dversion == 9, 'New user is on dversion 10.' );
ok( DW::Auth::Password->set( $u, 'test' ), 'Able to set password.' );
ok( DW::Auth::Password->check( $u, 'test' ), 'Password validates.' );
ok( !DW::Auth::Password->check( $u, 'test?' ), 'Password fails validation.' );

# Test hpassword works now
ok( DW::Auth::Password->check( $u, md5_hex('test'), allow_hpassword => 1 ),
    'hpassword does work for d9.' );

1;
