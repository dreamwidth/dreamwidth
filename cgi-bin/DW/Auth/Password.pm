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
use Digest::MD5 qw/ md5_hex /;

use DW::API::Key;
use DW::Auth::Helpers;

################################################################################
#
# public methods
#

sub check {
    my ( $class, $u, $password, %opts ) = @_;

    # Check that the provided password is valid.
    #
    # To support transitional clients, this method allows providing two options which
    # alter the behavior of password validation.
    #
    #   allow_hpassword      If truthy, will perform a secondary check to see if the user has
    #                        provided an MD5'd version of the password. This is used by some
    #                        clients that don't support challenge-response.
    #
    #   allow_api_keys       If truthy, will check the provided 'password' against the user's
    #                        generated API keys and return OK if any of them match.

    if ( $u->dversion <= 9 ) {
        return $class->_check_old_dversion( $u, $password, %opts );
    }

    return $class->_check_modern_dversion( $u, $password, %opts );
}

sub set {
    my ( $class, $u, $password, %opts ) = @_;

    my $dbh = LJ::get_db_writer()
        or $log->logcroak('Failed to get database writer.');

    if ( $u->dversion <= 9 && !$opts{force_bcrypt} ) {

        # Old style: Write raw password to the database and store it in the user
        # object. This is quite dumb, but it was the late 90s when this was written?
        $dbh->do( "REPLACE INTO password (userid, password) VALUES (?, ?)",
            undef, $u->userid, $password )
            or $log->logcroak('Failed to set password.');
    }
    else {
        my $encrypted_password_token =
            DW::Auth::Helpers->encrypt_token( $class->_bcrypt_password($password) );

        # Replace into database.
        $dbh->do( q{REPLACE INTO password2 (userid, version, password) VALUES (?, ?, ?)},
            undef, $u->userid, 1, $encrypted_password_token )
            or $log->logcroak( 'Failed to set password hash: ', $dbh->errstr );
    }

    return 1;
}

################################################################################
#
# internal methods
#
#

sub _check_old_dversion {
    my ( $class, $u, $password, %opts ) = @_;
    my $user_password = $class->_get_password($u);

    # Check bare (no options)
    my $crypt = Authen::Passphrase::Clear->new($user_password);
    return 1 if $crypt->match($password);

    # If allowing hpassword, try that
    if ( $opts{allow_hpassword} ) {
        my $crypt = Authen::Passphrase::Clear->new( md5_hex($user_password) );
        return 1 if $crypt->match($password);
    }

    # If allowing API keys, try each of those
    if ( $opts{allow_api_keys} ) {
        return 1 if $class->_check_api_keys( $u, $password, %opts );
    }

    # Failed all attempts at authentication
    return 0;
}

sub _check_modern_dversion {
    my ( $class, $u, $password, %opts ) = @_;

    # Modern usage, check standard password hash
    my $crypt = Authen::Passphrase::BlowfishCrypt->from_crypt( $class->_get_password_token($u) );
    return 1 if $crypt->match($password);

    # If allowing API keys, try each of those
    if ( $opts{allow_api_keys} ) {
        return 1 if $class->_check_api_keys( $u, $password, %opts );
    }

    return 0;
}

sub _check_api_keys {
    my ( $class, $u, $password, %opts ) = @_;

    my @keys = @{ DW::API::Key->get_keys_for_user($u) || [] };
    foreach my $key (@keys) {
        my $crypt = Authen::Passphrase::Clear->new( $key->hash );
        return 1 if $crypt->match($password);

        if ( $opts{allow_hpassword} ) {
            my $crypt = Authen::Passphrase::Clear->new( md5_hex( $key->hash ) );
            return 1 if $crypt->match($password);
        }
    }

    return 0;
}

sub _get_password {
    my ( $class, $u ) = @_;
    return unless $u->is_person;

    # This is only valid on dversion <= 9. Otherwise, we are using encrypted
    # passwords and this is meaningless.
    $log->logcroak('User password is unavailable.')
        unless $u->dversion <= 9;

    my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
    return $dbh->selectrow_array( q{SELECT password FROM password WHERE userid = ?},
        undef, $u->userid );
}

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
