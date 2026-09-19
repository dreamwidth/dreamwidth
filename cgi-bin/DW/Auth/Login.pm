#!/usr/bin/perl
#
# DW::Auth::Login
#
# Shared browser authentication and pending second-factor challenges.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Auth::Login;
use strict;
use v5.10;
use Digest::SHA qw(sha256_hex);
use Math::Random::Secure qw(irand);
use LJ::JSON;
use URI;
use DW::Auth::TOTP;
use DW::AccountSwitcher;

sub return_url {
    my ( $class, $url ) = @_;
    return unless defined $url && $url !~ /[\x00-\x20\x7f\\]/;
    return $url if $url =~ m{^/(?!/)};
    my $uri = URI->new($url);
    return unless $uri->scheme && $uri->scheme =~ /^https?$/;
    return if $uri->userinfo;
    my $host   = lc( $uri->host  // '' );
    my $domain = lc( $LJ::DOMAIN // '' );
    my $request_host = URI->new( 'http://' . DW::Request->get->host )->host;
    return $url
        if $host eq lc($request_host)
        || ( length $domain && ( $host eq $domain || $host =~ /\.\Q$domain\E$/ ) );
    return;
}

sub allowed {
    my ( $class, $u ) = @_;
    return
           $u
        && $u->is_person
        && !$u->is_expunged
        && !$u->is_memorial
        && !$u->is_locked
        && !$u->is_readonly;
}

sub _fingerprint {
    my ( $class, $u ) = @_;
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    my $row =
        $dbh->selectrow_hashref( 'SELECT password, totp_secret FROM password2 WHERE userid = ?',
        undef, $u->id );
    die 'Missing credentials' unless $row;
    return sha256_hex( join "\0", $row->{password}, $row->{totp_secret} // '' );
}

sub begin {
    my ( $class, $u, %opts ) = @_;
    return unless $class->allowed($u);
    my $token = join '', map { sprintf '%02x', irand(256) } 1 .. 32;
    my $dbh   = LJ::get_db_writer() or die 'Database unavailable';
    $opts{fingerprint} = $class->_fingerprint($u);
    $opts{browser}     = LJ::UniqCookie->current_uniq;
    $dbh->do( 'DELETE FROM login_challenges WHERE expires < ?', undef, time() )
        or die $dbh->errstr;
    $dbh->do(
        'INSERT INTO login_challenges (token, userid, payload, expires) VALUES (?, ?, ?, ?)',
        undef, sha256_hex($token), $u->id,
        to_json( \%opts ),
        time() + 300
    ) or die $dbh->errstr;
    return $token;
}

sub pending {
    my ( $class, $token ) = @_;
    return unless defined $token && $token =~ /^[a-f0-9]{64}$/;
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    my $row = $dbh->selectrow_hashref(
        'SELECT * FROM login_challenges WHERE token = ? AND expires > ? AND attempts < 5',
        undef, sha256_hex($token), time() )
        or return;
    my $opts = from_json( $row->{payload} );
    my $u    = LJ::load_userid( $row->{userid} );
    return unless $class->allowed($u) && DW::Auth::TOTP->is_enabled($u);
    return unless $opts->{fingerprint} eq $class->_fingerprint($u);
    return unless $opts->{browser} eq ( LJ::UniqCookie->current_uniq // '' );
    return ( $u, $opts );
}

sub verify {
    my ( $class, $token, $code ) = @_;
    my ( $u, $opts ) = $class->pending($token);
    return unless $u && !LJ::login_ip_banned($u);
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';

    # Count across challenges and IPs; issuing another challenge must not reset
    # the account's guessing budget. Serialize the reservation on its password row.
    $dbh->begin_work or die $dbh->errstr;
    my $reserved = eval {
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        my ($attempts) = $dbh->selectrow_array(
'SELECT COALESCE(SUM(attempts), 0) FROM login_challenges WHERE userid = ? AND expires > ?',
            undef, $u->id, time()
        );
        die $dbh->errstr if $dbh->err;
        my $rows = 0;
        if ( $attempts < 20 ) {
            $rows = $dbh->do(
'UPDATE login_challenges SET attempts = attempts + 1 WHERE token = ? AND attempts < 5 AND expires > ?',
                undef, sha256_hex($token), time()
            );
            die $dbh->errstr unless defined $rows;
        }
        $dbh->commit or die $dbh->errstr;
        $rows == 1;
    };
    if ($@) {
        my $error = $@;
        $dbh->rollback;
        die $error;
    }
    return unless $reserved;
    unless ( DW::Auth::TOTP->verify( $u, $code ) ) {
        LJ::handle_bad_login($u);
        return;
    }
    my $rows =
        $dbh->do( 'DELETE FROM login_challenges WHERE token = ?', undef, sha256_hex($token) );
    return unless $rows && $rows == 1;
    return ( $u, $opts );
}

# Only callers that have finished every required factor may call this method.
sub complete {
    my ( $class, $u, %opts ) = @_;
    return unless $class->allowed($u);
    my $mfa = DW::Auth::TOTP->is_enabled($u);
    return if $mfa && !$opts{mfa_verified};
    return if $opts{fingerprint} && $opts{fingerprint} ne $class->_fingerprint($u);
    my $remote = LJ::get_remote();
    if ( $opts{store_only} && $remote && !$remote->equals($u) ) {
        DW::AccountSwitcher->store_account( $u, $opts{exptype}, $opts{bindip} );
    }
    elsif ( $opts{adding} && $remote && !$remote->equals($u) ) {
        DW::AccountSwitcher->add_account( $u, $opts{exptype}, $opts{bindip} );
    }
    else {
        $u->make_login_session( $opts{exptype}, $opts{bindip} );
    }
    DW::Auth::TOTP->mark_session( $u, $u->session ) if $mfa;
    LJ::Hooks::run_hook( 'user_login', $u );
    my $uniq = DW::Request->get->note('uniq');
    LJ::MemCache::set( "loginout:$uniq", 1, time() + 15 ) if $uniq;
    return 1;
}
1;
