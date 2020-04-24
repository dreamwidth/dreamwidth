# t/blobstore.t
#
# Test some DW::Auth::Helpers functionality.
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

plan tests => 4;

use DW::Auth::Helpers;

# Check pepper keys
ok( DW::Auth::Helpers->_get_pepper_key eq 'A' x 32, 'Pepper key is right.' );
eval { DW::Auth::Helpers->_get_pepper_key(100) };
ok( $@, 'Invalid pepper key throws.' );

# Check encrypt/decrypt works
my $token1 = 'token';
my $enc1   = DW::Auth::Helpers->encrypt_token($token1);
ok( DW::Auth::Helpers->decrypt_token($enc1) eq $token1, 'Decryption works.' );

# Encrypting again results in different ciphertexts
ok( DW::Auth::Helpers->encrypt_token($token1) ne $enc1, 'Encryption results in new ciphertext.' );

1;
