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

use Crypt::AuthEnc::GCM qw/ gcm_encrypt_authenticate gcm_decrypt_verify /;
use Crypt::Mode::CBC;
use MIME::Base64 qw/ encode_base64 decode_base64 /;
use Math::Random::Secure qw(rand);

# Version prefix on the base64 string to distinguish formats.
# v1 (no prefix): legacy AES-CBC without authentication
# v2 ("2:" prefix): AES-GCM with 12-byte IV and 16-byte auth tag
my $GCM_PREFIX = '2:';

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

    # AES-GCM: authenticated encryption that prevents tampering.
    # 12-byte IV (NIST recommended for GCM), 16-byte auth tag.
    my $iv = pack( 'C*', map { rand(256) } 1 .. 12 );
    my ( $pkeyid, $pkey ) = $class->_get_pepper_key;

    my ( $ciphertext, $tag ) = gcm_encrypt_authenticate( 'AES', $pkey, $iv, '', $token );

    # Wire format: keyid[1] + iv[12] + tag[16] + ciphertext
    # Prefixed with "2:" before base64 to distinguish from v1 tokens.
    return $GCM_PREFIX . encode_base64( chr($pkeyid) . $iv . $tag . $ciphertext, '' );
}

sub decrypt_token {
    my ( $class, $encrypted_token ) = @_;

    if ( $encrypted_token =~ s/^\Q$GCM_PREFIX// ) {

        # v2: AES-GCM authenticated decryption
        my $raw        = decode_base64($encrypted_token);
        my $pkey       = $class->_get_pepper_key( ord( substr( $raw, 0, 1 ) ) );
        my $iv         = substr( $raw, 1, 12 );
        my $tag        = substr( $raw, 13, 16 );
        my $ciphertext = substr( $raw, 29 );

        my $plaintext = gcm_decrypt_verify( 'AES', $pkey, $iv, '', $ciphertext, $tag );
        $log->logcroak('GCM authentication failed: token has been tampered with')
            unless defined $plaintext;
        return $plaintext;
    }

    # v1 (legacy): AES-CBC without authentication, for existing DB-stored values.
    my $raw        = decode_base64($encrypted_token);
    my $aes        = Crypt::Mode::CBC->new('AES');
    my $pkey       = $class->_get_pepper_key( ord( substr( $raw, 0, 1 ) ) );
    my $iv         = substr( $raw, 1, 16 );
    my $ciphertext = substr( $raw, 17 );

    return $aes->decrypt( $ciphertext, $pkey, $iv );
}

1;
