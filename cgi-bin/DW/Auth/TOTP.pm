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
use Digest::SHA qw(sha256_hex);
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

# Login verification consumes a time step. Setup verification uses check_code instead.
sub verify {
    my ( $class, $u, $code ) = @_;
    return 0 unless defined $code && $class->is_enabled($u);
    $code =~ s/\s+//g;
    return $class->check_recovery_code( $u, lc $code )
        if $code =~ /^[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}$/;
    return 0 unless $code =~ /^[0-9]{6}$/;
    my $secret = decode_base32( $class->_get_secret($u) );
    my $oath   = Authen::OATH->new;
    my $step   = int( time() / 30 );
    my $dbh    = LJ::get_db_writer() or die 'Database unavailable';

    for my $candidate ( $step, $step - 1 ) {
        next unless $oath->totp( $secret, $candidate * 30 ) eq $code;
        $dbh->do( 'INSERT IGNORE INTO totp_used (userid, time_step) VALUES (?, 0)', undef, $u->id )
            or die $dbh->errstr;
        my $rows =
            $dbh->do( 'UPDATE totp_used SET time_step = ? WHERE userid = ? AND time_step < ?',
            undef, $candidate, $u->id, $candidate );
        die $dbh->errstr unless defined $rows;
        return $rows == 1 ? 1 : 0;
    }
    return 0;
}

sub check_recovery_code {
    my ( $class, $u, $code ) = @_;
    return 0 unless $u && $code;
    my $dbh  = LJ::get_db_writer() or die 'Database unavailable';
    my $rows = $dbh->selectcol_arrayref(
        "SELECT code FROM totp_recovery_codes WHERE userid = ? AND status = 'A'",
        undef, $u->id )
        or die $dbh->errstr;
    for my $encrypted (@$rows) {
        next unless DW::Auth::Helpers->decrypt_token($encrypted) eq $code;
        my $changed = $dbh->do(
"UPDATE totp_recovery_codes SET status = 'U', used_time = ? WHERE userid = ? AND code = ? AND status = 'A'",
            undef, time(), $u->id, $encrypted
        );
        die $dbh->errstr unless defined $changed;
        return 0 unless $changed == 1;
        $u->infohistory_add( '2fa_totp', 'recovery_code_used' );
        return 1;
    }
    return 0;
}

# Store proof on the server, not in caller-controlled cookie flags. Sessions
# created before MFA enforcement or before enrollment must not grant access.
sub mark_session {
    my ( $class, $u, $session ) = @_;
    my $secret = $class->_get_secret($u) or return;
    my $dbh    = LJ::get_db_writer()     or die 'Database unavailable';
    $dbh->do( 'DELETE FROM mfa_sessions WHERE expires < ?', undef, time() ) or die $dbh->errstr;
    $dbh->do( 'REPLACE INTO mfa_sessions (userid, sessid, factor, expires) VALUES (?, ?, ?, ?)',
        undef, $u->id, $session->id, sha256_hex($secret), $session->expiration_time )
        or die $dbh->errstr;
}

sub session_verified {
    my ( $class, $session ) = @_;
    my $u      = $session->owner;
    my $secret = $class->_get_secret($u);
    return 1 unless defined $secret;
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    my ($factor) =
        $dbh->selectrow_array( 'SELECT factor FROM mfa_sessions WHERE userid = ? AND sessid = ?',
        undef, $u->id, $session->id );
    return defined $factor && $factor eq sha256_hex($secret);
}

sub get_recovery_codes {
    my ( $class, $u ) = @_;

    my $dbh = LJ::get_db_writer() or $log->logcroak('Failed to get db writer.');
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

    $log->logcroak('Invalid TOTP secret')
        unless defined $secret && $secret =~ /^[a-zA-Z2-7]{26}(?:={6})?$/;

    # Set up TOTP for the user. Done in a transaction.
    my $dbh = LJ::get_db_writer() or $log->logcroak('Failed to get db writer.');

    $dbh->begin_work
        or $log->logcroak( 'Failed to start transaction: ', $dbh->errstr );

    my $saved = eval {
        my $updated = $dbh->do(
            q{UPDATE password2 SET totp_secret = ? WHERE userid = ? AND totp_secret IS NULL},
            undef, DW::Auth::Helpers->encrypt_token($secret), $userid );
        die 'TOTP enrollment requires an existing password and no configured factor'
            unless $updated && $updated == 1;

        $dbh->do( 'DELETE FROM mfa_sessions WHERE userid = ?', undef, $userid ) or die $dbh->errstr;
        $dbh->do( 'DELETE FROM totp_used WHERE userid = ?',    undef, $userid ) or die $dbh->errstr;
        $dbh->do( "UPDATE totp_recovery_codes SET status = 'X' WHERE userid = ? AND status = 'A'",
            undef, $userid )
            or die $dbh->errstr;

        # Now generate some recovery codes and insert into the database
        foreach ( 1 .. 10 ) {
            my $code = $class->_generate_recovery_code;
            $dbh->do( q{INSERT INTO totp_recovery_codes (userid, code, status) VALUES (?, ?, ?)},
                undef, $userid, DW::Auth::Helpers->encrypt_token($code), 'A' )
                or $log->logcroak( 'Failed to insert recovery code: ', $dbh->errstr );
        }

        $dbh->commit or $log->logcroak( 'Failed to commit: ', $dbh->errstr );
        1;
    };
    unless ($saved) {
        my $error = $@;
        $dbh->rollback;
        die $error;
    }

    $u->kill_all_sessions;
    $u->infohistory_add( '2fa_totp', 'enabled' );

    return 1;
}

sub disable {
    my ( $class, $u, $password, $code ) = @_;
    my $userid = $u->userid;
    my $dbh    = LJ::get_db_writer() or die 'Database unavailable';
    $dbh->begin_work or die $dbh->errstr;
    my $disabled = eval {

        # Serialize factor changes so a proof for an old factor cannot remove
        # a replacement factor enabled by a concurrent request.
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $userid );
        die $dbh->errstr if $dbh->err;
        unless ( DW::Auth::Password->check( $u, $password ) && $class->verify( $u, $code ) ) {
            $dbh->rollback;
            return undef;
        }

        # Wipe out their secret and also the recovery codes so they can't be used
        # in the future, this is done in a transaction to try to ensure we don't
        # end up in some mixed state with recovery codes still valid

        $dbh->do( q{UPDATE password2 SET totp_secret = NULL WHERE userid = ?}, undef, $userid )
            or $log->logcroak( 'Failed to disable TOTP: ', $dbh->errstr );
        $dbh->do( q{UPDATE totp_recovery_codes SET status = 'X' WHERE userid = ? AND status = 'A'},
            undef, $userid )
            or $log->logcroak( 'Failed to unset recovery codes:', $dbh->errstr );

        $dbh->commit or $log->logcroak( 'Failed to commit: ', $dbh->errstr );
        1;
    };
    unless ($disabled) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        die $error if $error;
        return undef;
    }

    $u->kill_all_sessions;
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

    die $dbh->errstr if $dbh->err;
    return defined $secret
        ? DW::Auth::Helpers->decrypt_token($secret)
        : undef;
}

sub _get_codes {
    my ( $class, $u, %opts ) = @_;

    # If the user does not have TOTP configured, return empty list
    my $secret = $opts{secret} // $class->_get_secret($u);
    return () unless defined $secret;

    return () unless $secret =~ /^[a-zA-Z2-7]{26}(?:={6})?$/;
    $secret = decode_base32($secret);

    # Allow the last code and the current code, just in case the user got
    # caught on a time boundary
    my $oath = Authen::OATH->new;
    return ( $oath->totp( $secret, time() - 30 ), $oath->totp($secret) );
}

1;
