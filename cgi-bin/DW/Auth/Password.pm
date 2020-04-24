#!/usr/bin/perl
#
# DW::Auth::Password
#
# Library for centralizing password storage code, so that this never leaks
# into other systems.
#
# TODO: We are recording a schema in the database in case we ever need to
# change how we store passwords, but for now, this module only ever sets it
# to 1 and never checks it.
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

package DW::Auth::Password;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Authen::Passphrase::Clear;
use Authen::Passphrase::BlowfishCrypt;
use Crypt::Mode::CBC;
use MIME::Base64 qw/ encode_base64 decode_base64 /;

################################################################################
#
# public methods
#

sub check_password {
    my ( $class, $u, $password ) = @_;

    my $crypt =
        $u->dversion <= 9
        ? Authen::Passphrase::Clear->new( $u->password )
        : Authen::Passphrase::BlowfishCrypt->from_crypt( $class->_password_hash($u) );

    return $crypt->match($password);
}

sub set_password {
    my ( $class, $u, $password ) = @_;

    my $encrypted_password_hash =
        $class->_encrypt_password_hash( $class->_bcrypt_password($password) );

    # Replace into database.
    my $dbh = LJ::get_db_writer()
        or $log->logcroak('Failed to get database writer.');
    $dbh->do( q{REPLACE INTO password2 (userid, version, password) VALUES (?, ?, ?)},
        undef, $u->userid, 1, $encrypted_password_hash )
        or $log->logcroak( 'Failed to set password hash: ', $dbh->errstr );
}

################################################################################
#
# internal methods
#

sub _password_hash {
    my ( $class, $u ) = @_;
    return unless $u->is_person;

    $log->logcroak('User password hash is unavailable.')
        unless $u->dversion >= 10;

    my $userid = $u->userid;
    my $dbh    = LJ::get_db_writer() or $log->logcroak("Couldn't get db master");

    return $class->_decrypt_password_hash(
        $dbh->selectrow_array(
            q{SELECT password FROM password2 WHERE userid = ? AND version = 1},
            undef, $userid
        )
    );
}

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

sub _bcrypt_password {
    my ( $class, $password ) = @_;

    # Applies bcrypt to a password, with a random salt

    my $crypt = Authen::Passphrase::BlowfishCrypt->new(
        cost        => $LJ::BCRYPT_COST,
        salt_random => 1,
        passphrase  => $password,
    );

    return $crypt->as_crypt;
}

sub _encrypt_password_hash {
    my ( $class, $password_hash ) = @_;

    # Applies symmetric encryption to the password hash
    my $aes = Crypt::Mode::CBC->new('AES');

    # Pick a random initialization vector (IV) every time we encrypt
    my $iv = pack( 'C*', map { rand(256) } 1 .. 16 );

    # The encryption key ("pepper key" here)
    my ( $pkeyid, $pkey ) = $class->_get_pepper_key;

    # Perform encryption, base64, and return
    my $ciphertext = $aes->encrypt( $password_hash, $pkey, $iv );
    return encode_base64( chr($pkeyid) . $iv . $ciphertext, '' );
}

sub _decrypt_password_hash {
    my ( $class, $encrypted_hash ) = @_;

    # Perform decoding, extraction, and decryption on the encrypted hash
    my $aes = Crypt::Mode::CBC->new('AES');
    $encrypted_hash = decode_base64($encrypted_hash);
    my $pkey       = $class->_get_pepper_key( ord( substr( $encrypted_hash, 0, 1 ) ) );
    my $iv         = substr( $encrypted_hash, 1, 16 );
    my $ciphertext = substr( $encrypted_hash, 17 );

    # Now decrypt
    return $aes->decrypt( $ciphertext, $pkey, $iv );
}

1;
