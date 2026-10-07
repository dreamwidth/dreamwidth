#!/usr/bin/perl
#
# DW::AccountSwitcher
#
# On-site multi-account session switching, in the spirit of GitHub's and
# Google's account switchers. A browser may hold sessions for several accounts
# at once and flip between them without re-entering a password.
#
# The model deliberately leaves the core auth path alone: the *active* account
# is still ljmastersession/ljloggedin, validated exactly as before. This module
# only tracks the *other* signed-in accounts, in a separate "ljsessions" cookie.
# Each stored account is a (userid, sessid, auth) handle -- the same secret
# ljmastersession already carries -- so the cookie is written http_only (and
# secure on HTTPS, via LJ::Session::set_cookie) and treated as credential
# material. Nothing is ever trusted from the cookie without re-validating the
# session against the database, the same way session_from_master_cookie does.
#
# Invariant: ljsessions never contains the active account; switching promotes a
# stored account to active and demotes the old active into the stored list.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::AccountSwitcher;

use strict;
use v5.10;

use DW::Cache;
use DW::Request;
use LJ::Session;

use constant COOKIE_NAME => 'ljsessions';
use constant COOKIE_VER  => 1;

# Cap the number of stored (non-active) accounts so the cookie stays small;
# each entry is a live credential, so a runaway list is also a liability.
use constant MAX_ACCOUNTS => 9;

################################################################################
# Cookie serialization
#
# Value: "v<ver>|<entry>|<entry>...//<cookie-gen>" where each entry is
# "u<userid>:s<sessid>:a<auth>". auth is alphanumeric (LJ::rand_chars) and the
# ids are integers, so "|" and ":" are unambiguous separators.
################################################################################

# Returns an arrayref of { userid, sessid, auth } hashes, unvalidated. Reads a
# write made earlier in this request first (the incoming cookie is stale once we
# have set a new one), then the incoming cookie.
sub _entries {
    my $class = shift;

    my $req = DW::Cache->request;
    return $req->get( 'account_switcher', 'entries' )
        if $req->has( 'account_switcher', 'entries' );

    my $entries = $class->_parse_cookie;
    $req->set( 'account_switcher', 'entries', $entries );
    return $entries;
}

sub _parse_cookie {
    my $class = shift;

    my $r = DW::Request->get or return [];
    my $val = $r->cookie(COOKIE_NAME) || '' or return [];

    my ( $body, $gen ) = split m!//!, $val, 2;
    return [] unless LJ::Session::valid_cookie_generation($gen);

    my ( $ver, @raw ) = split /\|/, $body;
    return [] unless defined $ver && $ver eq 'v' . COOKIE_VER;

    my @entries;
    foreach my $chunk (@raw) {
        my ( $userid, $sessid, $auth );
        my $dest = { u => \$userid, s => \$sessid, a => \$auth };

        my $bogus = 0;
        foreach my $field ( split /:/, $chunk ) {
            if ( $field =~ /^(\w)(.+)$/ && $dest->{$1} ) {
                ${ $dest->{$1} } = $2;
            }
            else {
                $bogus = 1;
            }
        }
        next if $bogus;
        next unless $userid && $userid =~ /^\d+$/ && $sessid && $sessid =~ /^\d+$/ && $auth;

        push @entries, { userid => $userid + 0, sessid => $sessid + 0, auth => $auth };
    }

    return \@entries;
}

# Persist the stored-account list. Empty list deletes the cookie. Also stashes
# the list in the request cache so later reads this request see it.
sub _write {
    my ( $class, $entries ) = @_;

    # keep only the most recently added accounts if we somehow overflow
    @$entries = @$entries[ -MAX_ACCOUNTS() .. -1 ] if @$entries > MAX_ACCOUNTS;

    DW::Cache->request->set( 'account_switcher', 'entries', $entries );

    my $domain = $LJ::DOMAIN_WEB || $LJ::DOMAIN;

    unless (@$entries) {
        LJ::Session::set_cookie(
            COOKIE_NAME() => "",
            domain        => $domain,
            path          => '/',
            delete        => 1,
        );
        return;
    }

    my $body = join '|', 'v' . COOKIE_VER,
        map { "u$_->{userid}:s$_->{sessid}:a$_->{auth}" } @$entries;
    my $value = $body . "//" . LJ::eurl( $LJ::COOKIE_GEN || "" );

    LJ::Session::set_cookie(
        COOKIE_NAME() => $value,
        domain        => $domain,
        path          => '/',
        http_only     => 1,
        expires       => LJ::Session->session_length('long'),
    );

    return;
}

# Delete the cookie entirely.
sub clear {
    my $class = shift;
    return $class->_write( [] );
}

################################################################################
# Validation / display
################################################################################

# Turn one raw entry into a display record, re-validating the session against
# the DB. Returns undef only if the user can't be loaded at all. An expired or
# otherwise unusable session still returns a record flagged not-valid, so the UI
# can list the account and route a click to a pre-filled login (Google-style).
sub _resolve {
    my ( $class, $entry ) = @_;

    my $u = LJ::load_userid( $entry->{userid} ) or return undef;

    my $valid = 0;
    my $sess;
    unless ( $u->is_expunged || $u->is_locked ) {
        $sess  = LJ::Session->instance( $u, $entry->{sessid} );
        $valid = 1
            if $sess && $sess->{auth} eq $entry->{auth} && $sess->valid;
    }

    return {
        u      => $u,
        userid => $u->userid,
        user   => $u->user,
        sess   => ( $valid ? $sess : undef ),
        valid  => $valid,
    };
}

# The other signed-in accounts, resolved for display. Skips the active remote
# defensively (the invariant already excludes it).
sub accounts {
    my $class = shift;

    my $remote    = LJ::get_remote();
    my $remote_id = $remote ? $remote->userid : 0;

    my @out;
    my %seen;
    foreach my $entry ( @{ $class->_entries } ) {
        next if $entry->{userid} == $remote_id;
        next if $seen{ $entry->{userid} }++;

        my $rec = $class->_resolve($entry) or next;
        push @out, $rec;
    }

    # sorted by username so the lists have a stable order and don't reshuffle as
    # accounts are added or switched (the cookie order changes; this doesn't).
    # Sort into an array first so scalar context still yields the count -- a bare
    # `return sort ...` is undef in scalar context.
    my @sorted = sort { $a->{user} cmp $b->{user} } @out;
    return @sorted;
}

################################################################################
# Mutations
################################################################################

# Make ($u, $sess) the active account: rewrite ljmastersession/ljloggedin/scheme
# and set the request remote. The session must already be validated.
sub _activate {
    my ( $class, $u, $sess ) = @_;
    $sess->update_master_cookie;
    LJ::set_remote($u);
    $u->{_session} = $sess;
    return;
}

# The (userid, sessid, auth) handle for the current active remote, or undef.
sub _current_handle {
    my $class  = shift;
    my $remote = LJ::get_remote() or return undef;
    my $sess   = $remote->session or return undef;
    return {
        userid => $remote->userid,
        sessid => $sess->id,
        auth   => $sess->auth,
    };
}

# Add a freshly-authenticated account and make it active, demoting the current
# active into the stored list. $u must already be password-verified by the
# caller. Returns 1.
sub add_account {
    my ( $class, $u, $exptype, $ipfixed ) = @_;

    my @list = grep { $_->{userid} != $u->userid } @{ $class->_entries };

    # demote the account we're currently logged in as
    if ( my $cur = $class->_current_handle ) {
        push @list, $cur unless $cur->{userid} == $u->userid;
    }
    $class->_write( \@list );

    # make_login_session creates a new session for $u, writes the master cookie,
    # and sets the remote -- exactly like a normal login.
    $u->make_login_session( $exptype, $ipfixed );

    return 1;
}

# Switch the active account to a stored one. Returns:
#   1          -- switched
#   'expired'  -- account is stored but its session is no longer usable
#   0          -- not a stored account
sub switch_to {
    my ( $class, $userid ) = @_;
    $userid += 0;

    my @entries = @{ $class->_entries };
    my ($target) = grep { $_->{userid} == $userid } @entries;
    return 0 unless $target;

    my $rec = $class->_resolve($target);
    return 'expired' unless $rec && $rec->{valid};

    # demote current active, drop the target from the stored list
    my @list = grep { $_->{userid} != $userid } @entries;
    if ( my $cur = $class->_current_handle ) {
        push @list, $cur unless $cur->{userid} == $userid;
    }
    $class->_write( \@list );

    $class->_activate( $rec->{u}, $rec->{sess} );
    return 1;
}

# After the active account has logged out, promote the first usable stored
# account to active. Returns the promoted LJ::User, or undef if none is usable
# (in which case the caller finishes a normal logout). Does NOT demote the old
# active -- it is already gone.
sub promote_next {
    my $class = shift;

    my @entries = @{ $class->_entries };
    foreach my $entry (@entries) {
        my $rec = $class->_resolve($entry);
        next unless $rec && $rec->{valid};

        my @list = grep { $_->{userid} != $entry->{userid} } @entries;
        $class->_write( \@list );
        $class->_activate( $rec->{u}, $rec->{sess} );
        return $rec->{u};
    }

    return undef;
}

# Remove one stored account from this browser without touching the active one:
# destroy its session and drop it from the list. Returns 1 if it was present.
sub remove_account {
    my ( $class, $userid ) = @_;
    $userid += 0;

    my @entries = @{ $class->_entries };
    my ($target) = grep { $_->{userid} == $userid } @entries;
    return 0 unless $target;

    my $rec = $class->_resolve($target);
    $rec->{sess}->destroy if $rec && $rec->{sess};

    $class->_write( [ grep { $_->{userid} != $userid } @entries ] );
    return 1;
}

1;
