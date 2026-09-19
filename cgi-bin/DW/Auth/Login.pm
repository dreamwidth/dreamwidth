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
use MIME::Base64 qw(encode_base64 decode_base64);
use Math::Random::Secure qw(irand);
use LJ::JSON;
use URI;
use DW::Auth::TOTP;
use DW::Auth::Challenge;
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
        && ( $u->is_person || ( $u->is_community && LJ::is_enabled('community-logins') ) )
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
    my $fingerprint = sha256_hex( join "\0", $row->{password}, $row->{totp_secret} // '' );
    my $factor = defined $row->{totp_secret} ? sha256_hex( $row->{totp_secret} ) : '';
    return wantarray ? ( $fingerprint, $factor ) : $fingerprint;
}

sub begin {
    my ( $class, $u, %opts ) = @_;
    return unless $class->allowed($u) && $u->is_person;
    my $token          = join '', map { sprintf '%02x', irand(256) } 1 .. 32;
    my $dbh            = LJ::get_db_writer() or die 'Database unavailable';
    my $check_password = exists $opts{password};
    my $password       = delete $opts{password};
    $dbh->begin_work or die $dbh->errstr;
    my $created = eval {
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        if ( $check_password && !DW::Auth::Password->check( $u, $password ) ) {
            $dbh->rollback;
            return undef;
        }
        @opts{qw(fingerprint factor)} = $class->_fingerprint($u);
        $opts{browser} = LJ::UniqCookie->current_uniq;
        $dbh->do( 'DELETE FROM login_challenges WHERE expires < ?', undef, time() )
            or die $dbh->errstr;
        $dbh->do(
            'INSERT INTO login_challenges (token, userid, payload, expires) VALUES (?, ?, ?, ?)',
            undef, sha256_hex($token), $u->id,
            to_json( \%opts ),
            time() + 300
        ) or die $dbh->errstr;
        $dbh->commit or die $dbh->errstr;
        1;
    };
    unless ($created) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        die $error if $error;
        return;
    }
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
    return unless $class->allowed($u) && $u->is_person && DW::Auth::TOTP->is_enabled($u);
    return unless $opts->{fingerprint} eq $class->_fingerprint($u);
    return unless $opts->{browser} eq ( LJ::UniqCookie->current_uniq // '' );
    return ( $u, $opts );
}

sub verify {
    my ( $class, $token, $code ) = @_;
    my ( $u, $opts ) = $class->pending($token);
    return unless $u && !LJ::login_ip_banned($u);
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';

    # Hold the account lock through challenge consumption and factor use. A
    # second request must recheck the challenge after acquiring that lock.
    $dbh->begin_work or die $dbh->errstr;
    my $bad_code;
    my $verified = eval {
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        my ($current)  = $class->pending($token);
        my ($attempts) = $dbh->selectrow_array(
'SELECT COALESCE(SUM(attempts), 0) FROM login_challenges WHERE userid = ? AND expires > ?',
            undef, $u->id, time()
        );
        die $dbh->errstr if $dbh->err;
        my $success = 0;
        if ( $current && $attempts < 20 ) {
            $dbh->do( 'UPDATE login_challenges SET attempts = attempts + 1 WHERE token = ?',
                undef, sha256_hex($token) )
                or die $dbh->errstr;
            if ( DW::Auth::TOTP->verify( $u, $code ) ) {
                my $rows = $dbh->do( 'DELETE FROM login_challenges WHERE token = ?',
                    undef, sha256_hex($token) );
                die 'Unable to consume login challenge' unless $rows && $rows == 1;
                $success = 1;
            }
            else {
                $bad_code = 1;
            }
        }
        $dbh->commit or die $dbh->errstr;
        $success;
    };
    if ($@) {
        my $error = $@;
        $dbh->rollback;
        die $error;
    }
    LJ::handle_bad_login($u) if $bad_code;
    return unless $verified;
    return ( $u, $opts );
}

# This signed cookie carries navigation only, never authorization. It outlives
# the consumable MFA challenge so a restart can still return to a comment draft.
sub restart_token {
    my ( $class, %opts ) = @_;
    my %restart = (
        browser    => LJ::UniqCookie->current_uniq,
        returnto   => $class->return_url( $opts{returnto} ),
        adding     => $opts{adding} ? 1 : 0,
        store_only => $opts{store_only} ? 1 : 0,
    );
    return DW::Auth::Challenge->generate( 3600, encode_base64( to_json( \%restart ), '' ) );
}

sub restart_url {
    my ( $class, $token ) = @_;
    my $fallback = "$LJ::SITEROOT/login";
    return $fallback
        unless defined $token
        && $token =~ /^c0:[0-9]+:[0-9]+:[0-9]+:[^:]+:[a-f0-9]{32}$/;
    my $check = { dont_check_count => 1 };
    DW::Auth::Challenge->check( $token, $check );
    return $fallback unless $check->{valid} && !$check->{expired};
    my $opts = eval { from_json( decode_base64( DW::Auth::Challenge->get_attributes($token) ) ) };
    return $fallback
        unless ref $opts eq 'HASH'
        && ( $opts->{browser} // '' ) eq ( LJ::UniqCookie->current_uniq // '' );
    my @query;
    push @query, 'switch=1'     if $opts->{adding};
    push @query, 'store_only=1' if $opts->{store_only};
    my $returnto = $class->return_url( $opts->{returnto} );
    push @query, 'returnto=' . LJ::eurl($returnto) if $returnto;
    return $fallback . ( @query ? '?' . join( '&', @query ) : '' );
}

# Only callers that have finished every required factor may call this method.
sub complete {
    my ( $class, $u, %opts ) = @_;
    return unless $class->allowed($u);
    my $remote           = LJ::get_remote();
    my $previous_session = $u->{_session};
    my $session;
    my $dbh      = LJ::get_db_writer() or die 'Database unavailable';
    my $prepared = eval {
        $dbh->begin_work or die $dbh->errstr;
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid = ? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        my $mfa = DW::Auth::TOTP->is_enabled($u);
        die 'Second factor required' if $mfa && ( !$opts{mfa_verified} || !$opts{factor} );
        die 'Credentials changed'
            if exists $opts{password}
            && !DW::Auth::Password->check( $u, $opts{password} );
        die 'Credentials changed'
            if $opts{fingerprint}
            && $opts{fingerprint} ne $class->_fingerprint($u);
        $session = LJ::Session->create(
            $u,
            exptype     => $opts{exptype} || 'short',
            ipfixed     => $opts{bindip},
            defer_login => 1
        ) or die 'Unable to create session';
        die 'Unable to verify session'
            if $mfa
            && !DW::Auth::TOTP->mark_session( $u, $session, $opts{factor} );
        $dbh->commit or die $dbh->errstr;
        die 'Session no longer valid' unless $session->valid;
        1;
    };
    unless ($prepared) {
        $dbh->rollback unless $dbh->{AutoCommit};
        eval { $session->destroy } if $session;
        $u->{_session} = $previous_session;
        return;
    }
    if ( $opts{store_only} && $remote && !$remote->equals($u) ) {
        DW::AccountSwitcher->store_account( $u, $opts{exptype}, $opts{bindip}, $session );
    }
    elsif ( $opts{adding} && $remote && !$remote->equals($u) ) {
        DW::AccountSwitcher->add_account( $u, $opts{exptype}, $opts{bindip}, $session );
    }
    else {
        $u->publish_login_session($session);
    }
    $u->record_login( $session->id );
    LJ::mark_user_active( $u, 'login' );
    LJ::Hooks::run_hook( 'user_login', $u );
    my $uniq = DW::Request->get->note('uniq');
    LJ::MemCache::set( "loginout:$uniq", 1, time() + 15 ) if $uniq;
    return 1;
}
1;
