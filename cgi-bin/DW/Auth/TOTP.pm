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

# Verification consumes a time step; setup consumes its code in the enrollment transaction.
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

# Cache the encrypted factor's digest, not the secret. A new encryption of the
# same secret has a different digest, so reenrollment cannot reuse old proofs.
sub _factor_state {
    my ( $class, $u, $refresh ) = @_;
    my $key    = [ $u->id, 'mfa-factor:' . $u->id ];
    my $cached = LJ::MemCache::get($key) unless $refresh;
    return $cached if $cached && !$cached->{changing};

    # A worker can die after publishing a change marker. Taking the account
    # lock below waits for any live transaction, then recovers from the DB.
    $refresh = 1 if $cached && $cached->{changing};
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';

    # A caller may already hold the account lock while preparing a session.
    # Read within that transaction without publishing uncommitted factor state.
    unless ( $dbh->{AutoCommit} ) {
        my ($encrypted) =
            $dbh->selectrow_array( 'SELECT totp_secret FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        return { factor => defined $encrypted ? sha256_hex($encrypted) : '' };
    }

    # Serialize cache publication with factor changes. Publishing under the
    # account lock prevents a slow refresh from replacing a newer factor state.
    $dbh->begin_work or die $dbh->errstr;
    my $state = eval {
        my ($encrypted) =
            $dbh->selectrow_array( 'SELECT totp_secret FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        my $current = { factor => defined $encrypted ? sha256_hex($encrypted) : '' };
        if ($refresh) {
            LJ::MemCache::set( $key, $current, 300 );
        }
        else {
            LJ::MemCache::add( $key, $current, 300 );
            $current = LJ::MemCache::get($key) || $current;
        }
        $dbh->commit or die $dbh->errstr;
        $current;
    };
    unless ($state) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        die $error;
    }
    return $state;
}

# A committed factor change remains successful if this cache repair fails.
# The change marker makes the next reader recover under the account lock.
sub _refresh_factor_state {
    my ( $class, $u ) = @_;
    eval { $class->_factor_state( $u, 1 ); 1 }
        or $log->warn( 'Unable to refresh factor cache for user ' . $u->id . ': ' . $@ );
}

sub _factor_changing {
    my ( $class, $u ) = @_;

    # With no cache configured there can be no stale cached factor state.
    return 1 unless @LJ::MEMCACHE_SERVERS;
    LJ::MemCache::set( [ $u->id, 'mfa-factor:' . $u->id ], { changing => 1 }, 300 )
        or die 'Unable to publish factor change marker';
    return 1;
}

sub _proof_key {
    my ( $class, $userid, $sessid ) = @_;

    # Separate entries that contain deadlines from the older factor-only cache.
    return [ $userid, "mfa-proof-v2:$userid:$sessid" ];
}

# Store factor-bound authorization on the server, never in cookie flags.
# Callers verify MFA or use the existing trusted admin/API authentication paths.
sub mark_session {
    my ( $class, $u, $session, $verified_factor ) = @_;
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    my ($encrypted) = $dbh->selectrow_array( 'SELECT totp_secret FROM password2 WHERE userid = ?',
        undef, $u->id );
    die $dbh->errstr if $dbh->err;
    return unless defined $encrypted;
    my $factor = sha256_hex($encrypted);
    return unless defined $verified_factor && $verified_factor eq $factor;
    my $expires = $session->expiration_time;
    return unless $expires > time();

    # Bound cleanup work while collecting expired proofs for inactive accounts too.
    $dbh->do( 'DELETE FROM mfa_sessions WHERE expires < ? LIMIT 1000', undef, time() )
        or die $dbh->errstr;
    $dbh->do( 'REPLACE INTO mfa_sessions (userid, sessid, factor, expires) VALUES (?, ?, ?, ?)',
        undef, $u->id, $session->id, $factor, $expires )
        or die $dbh->errstr;
    LJ::MemCache::set(
        $class->_proof_key( $u->id, $session->id ),
        { factor => $factor, expires => $expires },
        _proof_ttl($expires)
    );
    return 1;
}

# Called only by the existing privileged fake-login path, never from a cookie flag.
sub authorize_impersonation {
    my ( $class, $u, $session ) = @_;
    return 1 unless $class->is_enabled($u);
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    $dbh->begin_work or die $dbh->errstr;
    my $ok = eval {
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid=? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        my $factor = $class->_factor_state($u)->{factor};
        $class->mark_session( $u, $session, $factor )
            or die 'Unable to authorize impersonation'
            if $factor;
        $dbh->commit or die $dbh->errstr;
        1;
    };
    unless ($ok) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        eval { $session->destroy };
        die $error;
    }
    return 1;
}

sub session_verified {
    my ( $class, $session ) = @_;
    my $u     = $session->owner;
    my $state = $class->_factor_state($u);
    return 0 if $state->{changing};
    return 1 unless $state->{factor};
    my $proof = $class->_session_proof($session);
    return $proof->{factor} eq $state->{factor};
}

sub _session_proof {
    my ( $class, $session ) = @_;
    my $u     = $session->owner;
    my $key   = $class->_proof_key( $u->id, $session->id );
    my $proof = LJ::MemCache::get($key);
    unless ($proof) {
        my $dbh = LJ::get_db_writer() or die 'Database unavailable';
        my ( $factor, $expires ) = $dbh->selectrow_array(
            'SELECT factor, expires FROM mfa_sessions WHERE userid = ? AND sessid = ?',
            undef, $u->id, $session->id );
        die $dbh->errstr if $dbh->err;
        $proof = $factor
            && $expires > time() ? { factor => $factor, expires => $expires } : { factor => '' };
        LJ::MemCache::add( $key, $proof, _proof_ttl( $proof->{expires} ) );
        $proof = LJ::MemCache::get($key) || $proof;
    }
    return { factor => '' } unless ( $proof->{expires} // 0 ) > time();
    return $proof;
}

sub _proof_ttl {
    my ($expires) = @_;
    return 300 unless $expires;
    my $remaining = $expires - time();
    return $remaining > 300 ? 300 : $remaining > 0 ? $remaining : 1;
}

sub update_session_expiration {
    my ( $class, $session ) = @_;
    return 1 unless $class->_factor_state( $session->owner )->{factor};
    my $key = $class->_proof_key( $session->{userid}, $session->id );
    LJ::MemCache::delete($key);
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';

    # Renewal may extend a live proof, but cannot revive one that already expired.
    $dbh->do( 'UPDATE mfa_sessions SET expires = ? WHERE userid = ? AND sessid = ? AND expires > ?',
        undef, $session->expiration_time, $session->{userid}, $session->id, time() )
        or die $dbh->errstr;
    LJ::MemCache::delete($key);
    return 1;
}

sub get_recovery_codes {
    my ( $class, $u ) = @_;

    my $dbh   = LJ::get_db_writer() or $log->logcroak('Failed to get db writer.');
    my $codes = $dbh->selectcol_arrayref(
        q{SELECT code FROM totp_recovery_codes WHERE userid = ? AND status = 'A'},
        undef, $u->userid )
        or $log->logcroak( 'Failed to read recovery codes: ', $dbh->errstr );
    return map { DW::Auth::Helpers->decrypt_token($_) } @$codes;

}

# Check both credentials and read the remaining codes under the same account
# lock as password changes and factor replacement.
sub recovery_codes_for_credentials {
    my ( $class, $u, $password, $code ) = @_;
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    $dbh->begin_work or die $dbh->errstr;
    my $codes = eval {
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        unless ( DW::Auth::Password->check( $u, $password ) && $class->verify( $u, $code ) ) {
            $dbh->rollback;
            return undef;
        }
        my $remaining = [ $class->get_recovery_codes($u) ];
        $dbh->commit or die $dbh->errstr;
        $remaining;
    };
    if ($@) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        die $error;
    }
    return $codes;
}

# Enrollment verifies the current browser. Keep it signed in while invalidating
# other sessions; callers without a browser retain the existing all-session cleanup.
sub _revoke_other_sessions {
    my ( $class, $u, $preserve ) = @_;
    unless ($preserve) {
        $u->kill_all_sessions or die 'Unable to revoke account sessions';
        return 1;
    }
    die 'Session owner mismatch' unless $preserve->owner->equals($u);
    my $ids = $u->selectcol_arrayref( 'SELECT sessid FROM sessions WHERE userid=? AND sessid<>?',
        undef, $u->id, $preserve->id )
        or die $u->errstr;
    LJ::Session->destroy_sessions( $u, @$ids ) or die 'Unable to revoke account sessions';
    return 1;
}

sub enable {
    my ( $class, $u, $secret, $password, $preserve, $setup_code ) = @_;
    my $check_password = @_ > 3;
    my $userid         = $u->userid;

    return undef if $class->is_enabled($u);

    $log->logcroak('Invalid TOTP secret')
        unless defined $secret && $secret =~ /^[a-zA-Z2-7]{26}(?:={6})?$/;

    # Set up TOTP for the user. Done in a transaction.
    my $dbh = LJ::get_db_writer() or $log->logcroak('Failed to get db writer.');

    $dbh->begin_work
        or $log->logcroak( 'Failed to start transaction: ', $dbh->errstr );

    my $saved = 0;
    eval {
        ENROLL: {
            $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
                undef, $userid );
            die $dbh->errstr if $dbh->err;
            last ENROLL if $check_password && !DW::Auth::Password->check( $u, $password );
            $class->_factor_changing($u);
            my $updated = $dbh->do(
                q{UPDATE password2 SET totp_secret = ? WHERE userid = ? AND totp_secret IS NULL},
                undef, DW::Auth::Helpers->encrypt_token($secret), $userid );
            die $dbh->errstr unless defined $updated;
            last ENROLL unless $updated == 1;

            $dbh->do( 'DELETE FROM mfa_sessions WHERE userid = ?', undef, $userid )
                or die $dbh->errstr;
            $dbh->do( 'DELETE FROM totp_used WHERE userid = ?', undef, $userid )
                or die $dbh->errstr;
            last ENROLL if defined $setup_code && !$class->verify( $u, $setup_code );
            $dbh->do(
                "UPDATE totp_recovery_codes SET status = 'X' WHERE userid = ? AND status = 'A'",
                undef, $userid )
                or die $dbh->errstr;

            # Now generate some recovery codes and insert into the database
            foreach ( 1 .. 10 ) {
                my $code = $class->_generate_recovery_code;
                $dbh->do(
                    q{INSERT INTO totp_recovery_codes (userid, code, status) VALUES (?, ?, ?)},
                    undef, $userid, DW::Auth::Helpers->encrypt_token($code), 'A' )
                    or $log->logcroak( 'Failed to insert recovery code: ', $dbh->errstr );
            }

            # Revoke cluster sessions before committing the factor change. These
            # deletions cannot roll back with the central credential transaction:
            # a later failure can leave other browsers signed out without enabling 2FA.
            $class->_revoke_other_sessions( $u, $preserve );
            if ($preserve) {
                $class->mark_session( $u, $preserve, $class->_factor_state($u)->{factor} )
                    or die 'Unable to preserve verified enrollment session';
            }
            $dbh->commit or $log->logcroak( 'Failed to commit: ', $dbh->errstr );
            $saved = 1;
        }
    };
    unless ($saved) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        $class->_refresh_factor_state($u);
        die $error if $error;
        return undef;
    }

    $class->_refresh_factor_state($u);
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

        $class->_factor_changing($u);

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
        $class->_refresh_factor_state($u);
        die $error if $error;
        return undef;
    }

    $class->_refresh_factor_state($u);
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
