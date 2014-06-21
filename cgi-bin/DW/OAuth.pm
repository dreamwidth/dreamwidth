#!/usr/bin/perl
#
# DW::OAuth
#
# OAuth Helpers for Dreamwidth
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::OAuth;

use strict;
use warnings;
use DW::Request;
use Net::OAuth;

use DW::OAuth::Consumer;
use DW::OAuth::Request;
use DW::OAuth::Access;

use Digest::SHA qw/ sha1_hex sha1_base64 hmac_sha256 /;
use MIME::Base64::URLSafe;

use Carp qw/ croak /;

use DW::OAuth::LocalProtectedResourceRequest;
use Net::OAuth::V1_0A::AccessTokenRequest;
use Net::OAuth::V1_0A::RequestTokenRequest;

my %TOKEN_LENGTHS = (
    default => 16,
    access => 20,
);

my %CLASSES = (
    'protected resource' => 'DW::OAuth::LocalProtectedResourceRequest',
    'access token' => 'Net::OAuth::V1_0A::AccessTokenRequest',
    'request token' => 'Net::OAuth::V1_0A::RequestTokenRequest',
);

# FIXME: Until I figure our how to make Net::OAuth work with Hash::MultiValue
#  or reimplement it myself, if twisting Net::OAuth to our needs will be too much work
#  we can't accept duplicate keys.
#
# Otherwise we can't fully verify the signature, and even without this, the signature
#  probably would not verify anyway.
sub _process_into {
    my ( $out, $value ) = @_;

    my $data = $value->mixed;
    foreach my $key ( keys %$data ) {
        return 0 if exists $out->{$key};

        my $value = $data->{$key};
        return 0 if ref($value) eq "ARRAY";

        $out->{$key} = $value;
    }
    return 1;
}

sub get_request_raw {
    my ( $class, $method, $params, %opts ) = @_;
    my $args = $opts{args} // {};
    if ( ref $args ne 'HASH' ) {
        die "Invalid arguments: not hash";
    }

    my $authorization_header  = $opts{authorizaton_header} || "";

    my $valid_header =
        ( $authorization_header && $authorization_header =~ m/^OAuth / );
    my $oauth_attempted = $valid_header ||
        ( ( scalar grep { /^oauth_/ } keys %$args ) != 0 );
    return undef unless $oauth_attempted;

    my $consumer_key = $args->{oauth_consumer_key};
    if ( $valid_header ) {
        # FIXME: Get this another way.
        # This isn't really the best way to do this, but Net::OAuth will fail if the secret is missing.
        my ($key) = $authorization_header =~ m/oauth_consumer_key="(.+?)"/;
        $consumer_key = LJ::durl($key) if $key;
    }

    my $consumer = DW::OAuth::Consumer->from_token($consumer_key);
    my $oauth_token = $args->{oauth_token};
    if ( $valid_header ) {
        # FIXME: Get this another way.
        # This isn't really the best way to do this, but Net::OAuth will fail if the secret is missing.
        my ($key) = $authorization_header =~ m/oauth_token="(.+?)"/;
        $oauth_token = LJ::durl($key) if $key;
    }

    if ( $consumer ) {
        return (0,"consumer_unusable") unless $consumer->usable;
    } else {
        return (0,"consumer_notfound");
    }

    my $token;
    if ( $method eq 'protected resource' ) {
        $token = DW::OAuth::Access->from_token($oauth_token);
        if ( $token ) {
            return (0,"token_unusable") unless $token->usable( $consumer );
            $params->{token_secret} = $token->secret;
        } else {
            return (0,"token_notfound");
        }
    } elsif ( $method ne 'request token' ) {
        $token = DW::OAuth::Request->from_token($oauth_token);
        if ( $token ) {
            return (0,"token_unusable") unless $token->usable( $consumer );
            $params->{token_secret} = $token->secret;
            $params->{verifier} = $token->verifier;
        } else {
            return (0,"token_notfound");
        }
    }

    $params->{consumer_secret} = $consumer->secret;

    $params->{request_method} ||= $opts{method};
    $params->{request_url} ||=
        $opts{url} || LJ::create_url( undef, keep_args => 0 );

    $params->{signature_method} = 'HMAC-SHA1';

    my $oa_class = $CLASSES{ $method };
    die "Bad method $method" unless $oa_class;

    my $result = 0;
    eval {
        if ( $authorization_header ) {
            $params->{callback} ||= $args->{oauth_callback};
            $result = $oa_class->from_authorization_header(
                $authorization_header,
                protocol_version => Net::OAuth::PROTOCOL_VERSION_1_0A,
                %$params);
        } elsif ( defined $args->{oauth_signature} ) {
            $result = $oa_class->from_hash(
                $args,
                protocol_version => Net::OAuth::PROTOCOL_VERSION_1_0A,
                %$params);
        }
    };
    if ( $@ ) {
        warn $@;
        return (0,"oauth_failure: $@");
    }
    return (0,"oauth_failure: unknown") unless $result;
    return (0,"verify_failure") unless $result->verify;
    return (0,"nonce_failure") unless $class->verify_nonce( oauth => $result, token => $token );

    # http://oauth.googlecode.com/svn/spec/ext/body_hash/1.0/oauth-bodyhash.html
    my $inbound_type = $opts{content_type} || '';
    if ( $result->{body_hash} ) {
        return (0,"bodyhash_content")
            if $inbound_type =~ m!^application/x-www-form-urlencoded!i;

        croak "want_content missing" unless $opts{want_content};
        my $real_hash = sha1_base64( $opts{want_content}->() ) . '=';
        return (0,"bodyhash_hash") unless $real_hash eq $result->{body_hash};
    } else {
        return (0,"bodyhash_missing") if $inbound_type && $inbound_type !~ m!^application/x-www-form-urlencoded!i;
    }
    return ( $result, $consumer, $token );
}

sub get_request {
    my ( $class, $method, $params, %opts ) = @_;

    $params ||= {};

    my $r = DW::Request->get;

    my $args = $opts{args};
    if ( ! $args ) {
        $args = {};
        _process_into( $args, $r->get_args ) or return (0,"multi_arg");
        _process_into( $args, $r->post_args ) or return (0,"multi_arg")
            if $r->did_post;
    }

    return $class->get_request_raw($method,$params,
        args => $args,
        method => $r->method,
        authorizaton_header => $r->header_in("Authorization"),
        content_type => $r->header_in("Content-Type"),
        want_content => sub { return $r->content; }, 
        %opts);
}

sub _seperate_args {
    my $all_args = $_[0];
    my %out_args = ( extra_params => {} );

    foreach my $argname ( keys %$all_args ) {
        if ( $argname =~ m/^oauth_/ ) {
            $out_args{$argname} = $all_args->{$argname};
        } else {
            $out_args{extra_params}->{$argname} = $all_args->{$argname};
        }
    }

    return \%out_args;
}

sub user_for_protected_resource_raw {
    my ( $class, %opts ) = @_;

    my $args = ( delete $opts{args} );

    if ( ! defined $args ) {
        my $get_args  = delete $opts{get_args};
        my $post_args = delete $opts{post_args};
        $args = {};
        _process_into( $args, $get_args ) or return (0,"multi_arg")
            if $get_args;
        _process_into( $args, $post_args ) or return (0,"multi_arg")
            if $post_args;
    } elsif ( ref $args ne 'HASH' ) {
        die "Invalid arguments: not hash";
    }

    my $params = ( delete $opts{params} ) // {};
    if ( ref $params ne 'HASH' ) {
        die "Invalid params: not hash";
    }

    my %all_args = ( %$params, %$args );
    my $out_args = _seperate_args( \%all_args );

    my ( $result,@rest ) = $class->get_request_raw('protected resource', $out_args,
        args => $args,
        %opts );

    return undef unless defined $result;
    return (0,@rest) unless $result;

    my ( $consumer, $token ) = @rest;
    return (0,"token_missing") unless $token;
    return (0,"token_unusable") unless $token->usable( $consumer );

    unless ( $opts{no_store} ) {
        $class->current_token( $token );
        $token->update_accessed;
    }

    return ( 1, $token->user, $token );
}

sub user_for_protected_resource {
    my ( $class, $params, %opts ) = @_;

    my $r = DW::Request->get;

    my %ropts;
    $ropts{no_store} = $opts{no_store};
    $ropts{get_args} = $r->get_args;
    $ropts{post_args} = $r->post_args
        if $r->did_post;
    
    return $class->user_for_protected_resource_raw(
        %ropts,
        method => $r->method,
        authorizaton_header => $r->header_in("Authorization"),
        content_type => $r->header_in("Content-Type"),
        want_content => sub { return $r->content; } );
}

sub current_token {
    my $r = DW::Request->get;
    $r->pnote('oauth_token', $_[1])
        if exists $_[1];
    return $r->pnote('oauth_token');
}

sub verify_nonce {
    my ( $class, %opts ) = @_;

    my $timestamp = 0;
    my $nonce = 0;

    if ( $opts{oauth} ) {
        $timestamp = $opts{oauth}->timestamp;
        $nonce = $opts{oauth}->nonce;
    } else {
        $timestamp = ( $opts{timestamp} || 0 ) + 0;
        $nonce = $opts{nonce};
    }

    my $timestamp_valid = 30;            # 30 seconds should be plenty
    my $validity = 120;                  # 2 minutes, 4 times the timestamp validity.

    my $now = time();

    return 0 if abs( $now - $timestamp ) > $timestamp_valid;

    # Hash timestamp:nonce, don't want to put user-provided data directly in memcached
    my $key = "oauth_nonce:" . sha1_hex( "$timestamp:$nonce" );

    # this returns a false value if the key already exists
    return 0 unless LJ::MemCache::add($key,time(),$validity);
    return 1;
}

sub make_token_pair {
    my ( $class, $type, $data ) = @_;

    my $secret_key = 'oauth_' . $type;

    croak "No secret for type: $secret_key" unless $LJ::SECRETS{$secret_key};

    my $chars = $TOKEN_LENGTHS{ $type } || $TOKEN_LENGTHS{ default };

    my $token = LJ::rand_chars( $chars, 'urlsafe_b64' );

    # Signing this with a secret, so this is not just the token with things concatenated on.
    my $secret = urlsafe_b64encode( hmac_sha256( $token . LJ::rand_chars(32), $LJ::SECRETS{$secret_key} ) );

    return ( $token, $secret );
}

sub validate_token {
    return ( $_[1] =~ m/^[a-zA-Z0-9_\-]+$/ ) ? 1 : 0;
}

# Can this user view other OAuth authorizations/tokens
sub can_view_other {
    my $u = $_[1];
    return $u && $u->has_priv( "siteadmin", "oauth" );
}

# Seperate function, in case we ever want other logic
sub can_edit_other; *can_edit_other = \&can_view_other;

sub can_create_consumer {
    my $u = $_[1];
    return $u &&
        ! $u->is_inactive && ! LJ::sysban_check( 'oauth_consumer', $u->user );
}

1;
