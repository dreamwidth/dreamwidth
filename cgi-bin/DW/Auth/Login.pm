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
use DW::Cache;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

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
        $dbh->do( 'DELETE FROM login_challenges WHERE expires < ? LIMIT 1000', undef, time() )
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
    my ( $class, $token, $include_verified ) = @_;
    return unless defined $token && $token =~ /^[a-f0-9]{64}$/;
    my $dbh = LJ::get_db_writer() or die 'Database unavailable';
    my $row =
        $dbh->selectrow_hashref( 'SELECT * FROM login_challenges WHERE token = ? AND expires > ?',
        undef, sha256_hex($token), time() )
        or return;
    my $opts = from_json( $row->{payload} );
    return if $opts->{verified} ? !$include_verified : $row->{attempts} >= 5;
    $opts->{grant} = $token if $opts->{verified};
    my $u = LJ::load_userid( $row->{userid} );
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
    my ( $bad_code, $limit_reached );
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

                # Consume the factor once, retaining only a short-lived,
                # browser-bound grant until browser session publication succeeds.
                $opts->{verified} = 1;

                # Retain only the method, so completion can log recovery use after commit.
                $opts->{factor_method} = $code =~ /-/ ? 'recovery' : 'totp';
                my $rows = $dbh->do( 'UPDATE login_challenges SET payload = ? WHERE token = ?',
                    undef, to_json($opts), sha256_hex($token) );
                die 'Unable to verify login challenge' unless $rows && $rows == 1;
                $opts->{grant} = $token;
                $success = 1;
            }
            else {
                $bad_code      = 1;
                $limit_reached = $attempts + 1 == 20;
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
    $log->warn( 'event=mfa_attempt_limit userid=',
        $u->id, ' ip=', LJ::get_remote_ip() // 'unknown' )
        if $limit_reached;
    LJ::handle_bad_login($u) if $bad_code;
    return unless $verified;
    return ( $u, $opts );
}

# This signed cookie carries navigation only, never authorization. It outlives
# the consumable MFA challenge so a restart can still return to a comment draft.
sub restart_token {
    my ( $class, %opts ) = @_;
    my %restart = (
        browser  => LJ::UniqCookie->current_uniq,
        returnto => $class->return_url( $opts{returnto} ),
        adding   => $opts{adding} ? 1 : 0,
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
    push @query, 'switch=1' if $opts->{adding};
    my $returnto = $class->return_url( $opts->{returnto} );
    push @query, 'returnto=' . LJ::eurl($returnto) if $returnto;
    return $fallback . ( @query ? '?' . join( '&', @query ) : '' );
}

# Complete only a server-side verified, browser-bound second-factor grant.
sub complete {
    my ( $class, $u, %opts ) = @_;
    return unless $opts{grant};
    my $r        = DW::Request->get;
    my $remote   = LJ::get_remote();
    my $previous = $u->{_session};
    my @cookies  = $r->err_header_out('Set-Cookie');
    my $dbh      = LJ::get_db_writer() or die 'Database unavailable';
    my $session;
    my $stage     = 'begin_transaction';
    my $completed = eval {
        $dbh->begin_work or die $dbh->errstr;
        $stage = 'lock_credentials';
        $dbh->selectrow_array( 'SELECT userid FROM password2 WHERE userid=? FOR UPDATE',
            undef, $u->id );
        die $dbh->errstr if $dbh->err;
        $stage = 'validate_grant';
        my ( $owner, $grant ) = $class->pending( $opts{grant}, 1 );
        die 'Invalid login grant' unless $owner && $owner->equals($u) && $grant->{verified};
        %opts    = %$grant;
        $stage   = 'create_session';
        $session = LJ::Session->create(
            $u,
            exptype     => $opts{exptype} || 'short',
            ipfixed     => $opts{bindip},
            defer_login => 1
        ) or die 'Unable to create session';
        $stage = 'authorize_session';
        DW::Auth::TOTP->mark_session( $u, $session, $opts{factor} )
            or die 'Credentials changed';
        $stage = 'publish_session';

        if ( $opts{adding} && $remote && !$remote->equals($u) ) {
            DW::AccountSwitcher->add_account( $u, $opts{exptype}, $opts{bindip}, $session )
                or die 'Unable to add account';
        }
        else {
            $u->publish_login_session($session) or die 'Unable to publish session';
        }
        $stage = 'record_login';
        $u->record_login( $session->id );
        $stage = 'consume_grant';
        my $rows = $dbh->do( 'DELETE FROM login_challenges WHERE token=?',
            undef, sha256_hex( $opts{grant} ) );
        die 'Unable to consume login grant' unless $rows && $rows == 1;
        $stage = 'commit';
        $dbh->commit or die $dbh->errstr;
        1;
    };
    unless ($completed) {
        my $error = $@;

        # Exceptions can contain SQL parameters or credentials. Log the operation
        # and numeric DB error, not the exception text or challenge payload.
        my $context =
              ' userid='
            . $u->id
            . ' cluster='
            . $u->clusterid . ' ip='
            . ( LJ::get_remote_ip() // 'unknown' );
        if ( $error =~ /\A(?:Invalid login grant|Credentials changed)\b/ ) {
            $log->debug( 'event=mfa_login_rejected', $context, ' stage=', $stage );
        }
        else {
            $log->error(
                'event=mfa_login_failed', $context, ' stage=', $stage, ' db_errno=',
                $dbh->err // 0,
                ' cluster_errno=',
                $u->{_dbcm} ? ( $u->{_dbcm}->err // 0 ) : 0
            );
        }
        $dbh->rollback unless $dbh->{AutoCommit};
        if ($session) {
            my $destroyed = eval { $session->destroy };
            $log->error( 'event=mfa_session_cleanup_failed', $context, ' operation=browser_login' )
                unless $destroyed;
        }
        $u->{_session} = $previous;
        LJ::User->set_remote($remote);
        DW::Cache->request->clear_ns('account_switcher');
        $r->err_header_out( 'Set-Cookie', \@cookies );
        return;
    }
    $log->info( 'event=mfa_recovery_login userid=',
        $u->id, ' ip=', LJ::get_remote_ip() // 'unknown' )
        if ( $opts{factor_method} // '' ) eq 'recovery';
    LJ::Hooks::run_hook( 'user_login', $u );
    my $uniq = $r->note('uniq');
    LJ::MemCache::set( "loginout:$uniq", 1, time() + 15 ) if $uniq;
    return 1;
}

# Only protected-account login paths call this; ordinary forms stay unchanged.
sub required_message {
    return 'This account uses two-factor authentication. '
        . "Please <a href='$LJ::SITEROOT/login?switch=1'>log in</a> to post as this account.";
}

sub start_challenge {
    my ( $class, $u, %opts ) = @_;
    my $token = $class->begin( $u, %opts ) or die 'Unable to start second-factor login';
    my $r     = DW::Request->get;
    $r->add_cookie(
        name     => 'ljmfapending',
        value    => $token,
        httponly => 1,
        SameSite => 'Lax',
        path     => '/login'
    );
    $r->add_cookie(
        name     => 'ljmfarestart',
        value    => $class->restart_token(%opts),
        httponly => 1,
        SameSite => 'Lax',
        path     => '/login'
    );
    return $r->redirect("$LJ::SITEROOT/login/2fa");
}
1;
