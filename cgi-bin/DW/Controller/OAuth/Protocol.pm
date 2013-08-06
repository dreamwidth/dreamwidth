#!/usr/bin/perl
#
# DW::Controller::OAuth::Protocol
#
# Web-facing OAuth ( Protocol Methods )
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Controller::OAuth::Protocol;

use strict;
use warnings;
use DW::Routing;
use DW::Request;

use DW::OAuth;
use DW::OAuth::Consumer;
use DW::OAuth::Request;
use DW::OAuth::Access;

use LJ::JSON;

use DW::Controller;

# User facing
DW::Routing->register_string(
    "/oauth/authorize", \&authorize_handler, app => 1, prefer_ssl => 1 );

# API Callbacks
# IMPORTANT: These aren't prefer_ssl because the redirect may confuse a consumer.
DW::Routing->register_string(
    "/oauth/request_token", \&request_token_handler, app => 1, format => "plain" );
DW::Routing->register_string(
    "/oauth/access_token", \&access_token_handler, app => 1, format => "plain" );

# Authorization test endpoint
DW::Routing->register_string(
    "/oauth/test", \&test_handler, app => 1, format => "json" );

# None of the methods here call controller() intentionally
 
sub request_token_handler {
    my $r = DW::Request->get;

    $r->content_type( "text/plain" );

    my $args = $r->did_post ? $r->post_args : $r->get_args;

    my ($request,$consumer) = DW::OAuth->get_request( 'request token' );

    if ( ! defined $request ) {
        $r->status_line("400 Bad Request");
        $r->print( "Could not find/decode request" );
    } elsif ( !$request ) {
        $r->status_line("401 Unauthorized");
        $r->print( $consumer ); # also error 
    } else {
        # Service Provider sends Request Token Response
        my $request_token = DW::OAuth::Request->new(
            $consumer,
            callback => $request->callback,
            simple_token => $args->{simple_token} ? 1 : 0,
            simple_verifier => $args->{simple_verifier} ? 1 : 0,
        );
        $r->status_line("200 OK");
        my $response = Net::OAuth->response("request token")->new( 
            token => $request_token->token,
            token_secret => $request_token->secret,
            callback_confirmed => 'true',
            protocol_version => Net::OAuth::PROTOCOL_VERSION_1_0A,
        );

        # FIXME: Callbacks here
        $r->print($response->to_post_body);
    }

    return $r->OK;
}

sub access_token_handler {
    my $r = DW::Request->get;

    $r->content_type( "text/plain" );

    my ($request,@rest) = DW::OAuth->get_request( 'access token' );
    
    if ( ! defined $request ) {
        $r->status_line("400 Bad Request");
        $r->print( "Could not find/decode request" );
    } elsif ( !$request ) {
        $r->status_line("401 Unauthorized");
        $r->print( $rest[0] );
    } else {
        my ( $consumer, $token ) = @rest;
        # Service Provider sends Request Token Response
        my $access = DW::OAuth::Access->new($token);
        $access->reissue_token unless $access->token_valid;

        # Get rid of the request token
        $token->delete;

        $r->status_line("200 OK");
        my $response = Net::OAuth->response("access token")->new( 
            token => $access->token,
            token_secret => $access->secret,
            callback_confirmed => 'true',
            protocol_version => Net::OAuth::PROTOCOL_VERSION_1_0A,
            extra_params => {
                dw_username => $access->user->username,
                dw_userid => $access->user->id,
            },
        );

        $r->print($response->to_post_body);
    }

    return $r->OK;
}

sub authorize_handler {
    my $r = DW::Request->get;

    my $did_post = $r->did_post;
    my $args = $did_post ? $r->post_args : $r->get_args;

    # Because I want to be able to give the user instructions even if they must log in.
    my $anonymous = 1;
    $anonymous = 0 if $args->{allow} || $args->{deny};

    my ( $ok, $rv ) = controller( anonymous => $anonymous, form_auth => 1 );
    return $rv unless $ok;

    my $request = DW::OAuth::Request->from_token($args->{oauth_token});
    my $consumer = $request ? $request->consumer : undef;

    # even though $rv->{u} *should* be set, doesn't hurt to check it.
    if ( $consumer && $args->{allow} && $rv->{u} && $did_post ) {
        $request->userid( $rv->{u}->userid );
        $request->save;

        if ( $request->callback ne 'oob' ) {
            my $response = Net::OAuth->response("user auth")->new(
                token => $request->token,
                verifier => $request->verifier,
                protocol_version => Net::OAuth::PROTOCOL_VERSION_1_0A,
            );

            $r->content_type("text/html");
            $r->header_out('Location',$response->to_url($request->callback));
            return $r->REDIRECT;
        }
    } elsif ( $consumer && $args->{deny} && $did_post ) {
        $request->delete;

        if ( $request->callback ne 'oob' ) {
            my $response = Net::OAuth->response("user auth")->new(
                token => $request->token,
                verifier => '',
                protocol_version => Net::OAuth::PROTOCOL_VERSION_1_0A,
            );

            $r->content_type("text/html");
            $r->header_out('Location',$response->to_url($request->callback));
            return $r->REDIRECT;
        }
    }

    return DW::Template->render_template( 'oauth/authorize.tt', {
        %$rv,
        request => $request,
        consumer => $consumer,
        oauth_token => $args->{oauth_token},
        args => $args,
    });
}

sub test_handler {
    my $r = DW::Request->get;

    my $err = sub {
        my ($err,%rest) = @_;
        $r->print( to_json( { ok => 0, error => $err, %rest} ) );
        return $r->OK;
    };

    my ($res,$u) = DW::OAuth->user_for_protected_resource;

    return $err->("not_attempted") unless defined $res;
    return $err->($u) unless $res;

    $r->print( to_json(
        { ok => 1, username => $u->user, userid => $u->id } ) );
    return $r->OK;
}

1;
