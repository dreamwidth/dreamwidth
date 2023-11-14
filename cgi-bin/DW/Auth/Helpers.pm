#!/usr/bin/perl
#
# DW::Auth::Helpers
#
# Shared methods used by various authentication subsystems.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Auth::Helpers;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Crypt::Mode::CBC;
use MIME::Base64 qw/ encode_base64 decode_base64 /;
use Math::Random::Secure qw(rand);

################################################################################
#
# public methods
#

sub _get_pepper_key {
    my ( $class, $keyid ) = @_;

    $keyid //= $LJ::PASSWORD_PEPPER_KEY_CURRENT_ID;

    # Key is later encoded to a single byte, so if this doesn't fit, explode
    # very early on (here)
    $log->logcroak('Pepper key ID must be in the range 0..255')
        if $keyid < 0 || $keyid > 255;

    my $keyval = $LJ::PASSWORD_PEPPER_KEYS{$keyid}
        or $log->logcroak('Pepper key ID invalid, key not found?');
    return wantarray ? ( $keyid, $keyval ) : $keyval;
}

sub encrypt_token {
    my ( $class, $token ) = @_;

    # Applies symmetric encryption to the token
    my $aes = Crypt::Mode::CBC->new('AES');

    # Pick a random initialization vector (IV) every time we encrypt
    my $iv = pack( 'C*', map { rand(256) } 1 .. 16 );

    # The encryption key ("pepper key" here)
    my ( $pkeyid, $pkey ) = $class->_get_pepper_key;

    # Perform encryption, base64, and return
    my $ciphertext = $aes->encrypt( $token, $pkey, $iv );
    return encode_base64( chr($pkeyid) . $iv . $ciphertext, '' );
}

sub decrypt_token {
    my ( $class, $encrypted_token ) = @_;

    # Perform decoding, extraction, and decryption on the encrypted token
    my $aes = Crypt::Mode::CBC->new('AES');
    $encrypted_token = decode_base64($encrypted_token);
    my $pkey       = $class->_get_pepper_key( ord( substr( $encrypted_token, 0, 1 ) ) );
    my $iv         = substr( $encrypted_token, 1, 16 );
    my $ciphertext = substr( $encrypted_token, 17 );

    # Now decrypt
    return $aes->decrypt( $ciphertext, $pkey, $iv );
}

1;
