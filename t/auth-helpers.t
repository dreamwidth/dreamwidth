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

plan tests => 10;

use Crypt::Mode::CBC;
use Math::Random::Secure qw(rand);
use MIME::Base64 qw/ encode_base64 decode_base64 /;

use DW::Auth::Helpers;

# Check pepper keys
ok( DW::Auth::Helpers->_get_pepper_key eq 'A' x 32, 'Pepper key is right.' );
eval { DW::Auth::Helpers->_get_pepper_key(100) };
ok( $@, 'Invalid pepper key throws.' );

# Check encrypt/decrypt works (v2 GCM round-trip)
my $token1 = 'token';
my $enc1   = DW::Auth::Helpers->encrypt_token($token1);
ok( DW::Auth::Helpers->decrypt_token($enc1) eq $token1, 'Decryption works.' );

# Encrypting again results in different ciphertexts
ok( DW::Auth::Helpers->encrypt_token($token1) ne $enc1, 'Encryption results in new ciphertext.' );

# v2 format: token starts with "2:" prefix
ok( $enc1 =~ /^2:/, 'Encrypted token uses v2 (GCM) format prefix.' );

# v2 tamper detection: flipping a ciphertext byte causes decrypt to fail
my $raw1     = decode_base64( substr( $enc1, 2 ) );    # strip "2:" prefix
my $tampered = $raw1;
substr( $tampered, 29, 1, chr( ord( substr( $tampered, 29, 1 ) ) ^ 0xFF ) );
eval { DW::Auth::Helpers->decrypt_token( '2:' . encode_base64( $tampered, '' ) ) };
ok( $@ && $@ =~ /tampered/, 'Tampered v2 token is rejected.' );

# v1 backward compatibility: tokens encrypted with old AES-CBC format still decrypt
my $aes   = Crypt::Mode::CBC->new('AES');
my $iv    = pack( 'C*', map { rand(256) } 1 .. 16 );
my $pkey  = DW::Auth::Helpers->_get_pepper_key;
my $ct    = $aes->encrypt( $token1, $pkey, $iv );
my $v1enc = encode_base64( chr($LJ::PASSWORD_PEPPER_KEY_CURRENT_ID) . $iv . $ct, '' );
ok( DW::Auth::Helpers->decrypt_token($v1enc) eq $token1, 'Legacy v1 (CBC) tokens still decrypt.' );

# v2 round-trip with longer payload (JSON-like)
my $json_payload = '{"userid":12345,"password_ok":1,"timestamp":1700000000}';
my $enc_json     = DW::Auth::Helpers->encrypt_token($json_payload);
ok( DW::Auth::Helpers->decrypt_token($enc_json) eq $json_payload, 'JSON payload round-trips.' );

# v2 with empty payload
my $enc_empty = DW::Auth::Helpers->encrypt_token('');
ok( DW::Auth::Helpers->decrypt_token($enc_empty) eq '', 'Empty payload round-trips.' );

# v2 with binary payload
my $binary  = join( '', map { chr( rand(256) ) } 1 .. 100 );
my $enc_bin = DW::Auth::Helpers->encrypt_token($binary);
ok( DW::Auth::Helpers->decrypt_token($enc_bin) eq $binary, 'Binary payload round-trips.' );

1;
