#!/usr/bin/perl
#
# DW::Auth::TOTP
#
# Library for dealing with TOTP related code.
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

package DW::Auth::TOTP;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Authen::OATH;
use Convert::Base32 qw/ decode_base32 encode_base32 /;
use Math::Random::Secure qw/ rand irand /;

use DW::Auth::Helpers;
use DW::Auth::Password;

################################################################################
#
# public methods
#

sub is_enabled {
    my ( $class, $u ) = @_;

    return defined $class->_get_secret($u);
}

# Check that a TOTP code is valid. %opts may contain secret, which will
# be used as the secret to generate codes instead of whatever the user has
# configured. This is used in the setup flow when the user doesn't have a
# saved secret yet.
sub check_code {
    my ( $class, $u, $code, %opts ) = @_;

    foreach my $test_code ( $class->_get_codes( $u, secret => $opts{secret} ) ) {
        return 1 if $test_code eq $code;
    }
    return 0;
}

sub get_recovery_codes {
    my ( $class, $u ) = @_;

    my $dbh = LJ::get_db_writer() or $log->logroak('Failed to get db writer.');
    return map { DW::Auth::Helpers->decrypt_token($_) } @{
        $dbh->selectcol_arrayref(
            q{SELECT code FROM totp_recovery_codes WHERE userid = ? AND status = 'A'}, undef,
            $u->userid
            )
            || []
    };
}

sub enable {
    my ( $class, $u, $secret ) = @_;
    my $userid = $u->userid;

    $log->logcroak('2fa already enabled on user.')
        if $class->is_enabled($u);

    # Set up TOTP for the user. Done in a transaction.
    my $dbh = LJ::get_db_writer() or $log->logroak('Failed to get db writer.');

    $dbh->begin_work
        or $log->logcroak( 'Failed to start transaction: ', $dbh->errstr );

    $dbh->do(
        q{UPDATE password2 SET totp_secret = ? WHERE userid = ?}, undef,
        DW::Auth::Helpers->encrypt_token($secret),                $userid
    ) or $log->logcroak( 'Failed to set totp_secret: ', $dbh->errstr );

    # Now generate some recovery codes and insert into the database
    foreach ( 1 .. 10 ) {
        my $code = $class->_generate_recovery_code;
        $dbh->do( q{INSERT INTO totp_recovery_codes (userid, code, status) VALUES (?, ?, ?)},
            undef, $userid, DW::Auth::Helpers->encrypt_token($code), 'A' )
            or $log->logcroak( 'Failed to insert recovery code: ', $dbh->errstr );
    }

    $dbh->commit or $log->logcroak( 'Failed to commit: ', $dbh->errstr );

    $u->infohistory_add( '2fa_totp', 'enabled' );

    return 1;
}

sub disable {
    my ( $class, $u, $password ) = @_;
    my $userid = $u->userid;

    # Verify that their password is correct (we do this here to enforce that
    # the TOTP system never removes itself without knowledge of the user's
    # password)
    return undef
        unless DW::Auth::Password->check( $u, $password );

    # Wipe out their secret and also the recovery codes so they can't be used
    # in the future, this is done in a transaction to try to ensure we don't
    # end up in some mixed state with recovery codes still valid
    my $dbh = LJ::get_db_writer() or $log->logroak('Failed to get db writer.');

    $dbh->begin_work
        or $log->logcroak( 'Failed to start transaction: ', $dbh->errstr );

    $dbh->do( q{UPDATE password2 SET totp_secret = NULL WHERE userid = ?}, undef, $userid )
        or $log->logcroak( 'Failed to disable TOTP: ', $dbh->errstr );
    $dbh->do( q{UPDATE totp_recovery_codes SET status = 'X' WHERE userid = ? AND status = 'A'},
        undef, $userid )
        or $log->logcroak( 'Failed to unset recovery codes:', $dbh->errstr );

    $dbh->commit or $log->logcroak( 'Failed to commit: ', $dbh->errstr );

    $u->infohistory_add( '2fa_totp', 'disabled' );

    return 1;
}

sub generate_secret {
    my $class = $_[0];

    # For convenience, always deal with base32'd secrets, as specified
    # by Google Authenticator
    my $string;
    $string .= chr( irand(256) ) for 1 .. 16;
    return encode_base32($string);
}

################################################################################
#
# internal methods
#

sub _generate_recovery_code {
    my $class = $_[0];

    # For recovery, meant to be slightly easier for humans to type/write down
    # correctly
    my @chars = ( "a" .. "z", "0" .. "9" );

    my $string;
    $string = join( '-',
        join( '', map { $chars[ rand @chars ] } 1 .. 4 ),
        join( '', map { $chars[ rand @chars ] } 1 .. 4 ) );

    return $string;
}

sub _get_secret {
    my ( $class, $u ) = @_;

    my $dbh    = LJ::get_db_writer() or $log->logcroak('Failed to get db writer.');
    my $secret = $dbh->selectrow_array( q{SELECT totp_secret FROM password2 WHERE userid = ?},
        undef, $u->userid );

    return defined $secret
        ? DW::Auth::Helpers->decrypt_token($secret)
        : undef;
}

sub _get_codes {
    my ( $class, $u, %opts ) = @_;

    # If the user does not have TOTP configured, return empty list
    my $secret = $opts{secret} // $class->_get_secret($u);
    return () unless defined $secret;

    $secret = decode_base32($secret);

    # Allow the last code and the current code, just in case the user got
    # caught on a time boundary
    my $oath = Authen::OATH->new;
    return ( $oath->totp( $secret, time() - 30 ), $oath->totp($secret) );
}

1;
