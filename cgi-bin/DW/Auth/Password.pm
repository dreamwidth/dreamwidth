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

sub check_password {
    my ( $class, $u, $password ) = @_;

    my $crypt =
        $u->dversion <= 9
        ? Authen::Passphrase::Clear->new( $u->password )
        : Authen::Passphrase::BlowfishCrypt->from_crypt( $class->password_hash( $u ) );

    return $crypt->match($password);
}

sub password_hash {
    my ( $class, $u ) = @_;
    return unless $u->is_person;

    $log->logcroak('User password hash is unavailable.')
        unless $u->dversion >= 10;

    my $userid        = $u->userid;
    my $dbh           = LJ::get_db_writer() or $log->logcroak("Couldn't get db master");
    my $safe_password = decode_base64(
        $dbh->selectrow_array( q{SELECT password FROM password2 WHERE userid = ?}, undef, $userid )
    );

    my $aes        = Crypt::Mode::CBC->new('AES');
    my $pkey       = get_pepper_key( ord( substr( $safe_password, 0, 1 ) ) );
    my $iv         = substr( $safe_password, 1, 16 );
    my $ciphertext = substr( $safe_password, 17 );

    return $aes->decrypt( $ciphertext, $pkey, $iv );
}

sub get_pepper_key {
    my ( $class, $keyid ) = @_;

    $keyid //= $LJ::PASSWORD_PEPPER_KEY_CURRENT_ID;

    # Key is later encoded to a single byte, so if this doesn't fit, explode
    # very early on (here)
    $log->logcroak('Pepper key ID must be in the range 0..255')
        if $keyid < 0 || $keyid > 255;

    my $keyval = $LJ::PASSWORD_PEPPER_KEYS{$keyid};
    return wantarray ? ( $keyid, $keyval ) : $keyval;
}

sub set_password {
    my ( $class, $u, $password ) = @_;

    # Step 1)
    #
    # Use bcrypt with a random salt to construct a hash that we can use to
    # verify the password later. This step makes it so that we can never
    # retrieve the password.
    #
    my $crypt = Authen::Passphrase::BlowfishCrypt->new(
        cost        => $LJ::BCRYPT_COST,
        salt_random => 1,
        passphrase  => $password,
    );

    my $bcrypt_hash = $crypt->as_crypt;

    # Step 2)
    #
    # Now encrypt the password. This is equivalent to applying 'pepper',
    # which provides the property that if our database were to be
    # breached, the password fields are entirely useless unless the
    # attacker also was able to get access to the encryption key (which
    # is not stored in the database).

    # Perform the encryption with random IV.
    my $aes = Crypt::Mode::CBC->new('AES');
    my $iv  = pack( 'C*', map { rand(256) } 1 .. 16 );
    my ( $pkeyid, $pkey ) = $class->get_pepper_key();
    my $ciphertext = $aes->encrypt( $bcrypt_hash, $pkey, $iv );

    # Safe password is base64'd and includes the IV.
    my $safe_password = encode_base64( chr($pkeyid) . $iv . $ciphertext, '' );

    # Replace into database.
    my $dbh = LJ::get_db_writer()
        or $log->logcroak('Failed to get database writer.');
    $dbh->do( q{REPLACE INTO password2 (userid, version, password) VALUES (?, ?, ?)},
        undef, $u->userid, 1, $safe_password )
        or $log->logcroak('Failed to set password hash: ', $dbh->errstr);
}

1;
