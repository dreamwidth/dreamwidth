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

use DW::Auth::Helpers;

################################################################################
#
# public methods
#

sub check {
    my ( $class, $u, $password ) = @_;

    my $crypt =
        $u->dversion <= 9
        ? Authen::Passphrase::Clear->new( $u->password )
        : Authen::Passphrase::BlowfishCrypt->from_crypt( $class->_get_password_token($u) );

    return $crypt->match($password);
}

sub set {
    my ( $class, $u, $password ) = @_;

    my $encrypted_password_token =
        DW::Auth::Helpers->encrypt_token( $class->_bcrypt_password($password) );

    # Replace into database.
    my $dbh = LJ::get_db_writer()
        or $log->logcroak('Failed to get database writer.');
    $dbh->do( q{REPLACE INTO password2 (userid, version, password) VALUES (?, ?, ?)},
        undef, $u->userid, 1, $encrypted_password_token )
        or $log->logcroak( 'Failed to set password hash: ', $dbh->errstr );
}

################################################################################
#
# internal methods
#

sub _get_password_token {
    my ( $class, $u ) = @_;
    return unless $u->is_person;

    $log->logcroak('User password hash is unavailable.')
        unless $u->dversion >= 10;

    my $userid = $u->userid;
    my $dbh    = LJ::get_db_writer() or $log->logcroak("Couldn't get db master");

    return DW::Auth::Helpers->decrypt_token(
        $dbh->selectrow_array(
            q{SELECT password FROM password2 WHERE userid = ? AND version = 1},
            undef, $userid
        )
    );
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

1;
