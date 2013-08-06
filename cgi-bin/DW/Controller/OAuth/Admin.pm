#!/usr/bin/perl
#
# DW::Controller::OAuth::Admin
#
# Web-facing OAuth ( Admin/Consumer Methods )
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
package DW::Controller::OAuth::Admin;

use strict;
use warnings;
use DW::Routing;
use DW::Controller;
use DW::Request;

use DW::OAuth::Consumer;
use DW::OAuth::Access;

use DW::Controller::OAuth::User;

# User facing
DW::Routing->register_string(  "/admin/oauth/index", \&index_handler, app => 1, prefer_ssl => 1 );
DW::Controller::Admin->register_admin_page( '/',
    path => 'oauth/index',
    ml_scope => '/oauth/admin/index.tt',
    privs => [],
);

DW::Routing->register_redirect( "/admin/oauth/consumer/index", "/admin/oauth/" );

DW::Routing->register_string( "/admin/oauth/consumer/new",
    \&consumer_create_handler, app => 1, prefer_ssl => 1 );

DW::Routing->register_regex( qr!^/admin/oauth/consumer/(\d+)/?$!,
    \&consumer_handler, app => 1, prefer_ssl => 1 );
DW::Routing->register_regex( qr!^/admin/oauth/consumer/(\d+)/secret$!,
    \&consumer_secret_handler, app => 1, prefer_ssl => 1 );
DW::Routing->register_regex( qr!^/admin/oauth/consumer/(\d+)/reissue$!,
    \&consumer_reissue_handler, app => 1, prefer_ssl => 1 );
DW::Routing->register_regex( qr!^/admin/oauth/consumer/(\d+)/delete$!,
    \&consumer_delete_handler, app => 1 );



sub index_handler {
    my ( $ok, $rv ) = controller( );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $args = $r->get_args;

    my $u = $rv->{u};
    my $view_u = $u;

    my $view_other = DW::OAuth->can_view_other( $u );
    $view_u = LJ::load_user( $args->{user} )
        if $view_other && $args->{user};
    my $tokens = DW::OAuth::Consumer->tokens_for_user( $view_u );

    return DW::Template->render_template( 'oauth/admin/index.tt', {
        %$rv,
        view_other      => ! $u->equals( $view_u ),
        view_u          => $view_u,
        tokens          => $tokens,
        can_view_other  => $view_other,

        # This is for the viewing user, as this means nothing for view_other
        can_create      => DW::OAuth->can_create_consumer( $u ),
    });
}

sub consumer_handler {
    my $consumer_id = $_[1];

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};

    my $token = DW::OAuth::Consumer->from_id( $consumer_id );
    return $r->NOT_FOUND
        unless $token;

    my $can_view_other = DW::OAuth->can_view_other( $u );
    my $view_u = $token->owner;
    return $r->NOT_FOUND
        unless $can_view_other || $view_u->equals( $u );

    my $view_other = ! $view_u->equals( $u );
    my $edit_consumer = DW::OAuth->can_edit_other( $u );

    my $save_error;
    if ( $r->did_post ) {
        my $args = $r->post_args;
        unless ( $view_other ) {
            my $name = $args->{name};
            my $website = $args->{website};
            my $uri = URI->new($website);
            my $scheme = $uri->scheme;
            
            if ( $name && $scheme =~ m!^https?$! ) {
                $token->name( $args->{name} );

                $token->website( $args->{website} );
            
                $token->active( $args->{active} ? 1 : 0 );
            } else {
                $save_error = "Invalid name or website";
            }
        }

        if ( $edit_consumer ) {
            $token->approved( $args->{approved} ? 1 : 0 );
        }
        $token->save;
    }

    return DW::Template->render_template( 'oauth/admin/consumer.tt', {
        %$rv,
        view_other      => $view_other,
        view_consumer   =>
            $can_view_other || $token->owner->equals( $u ),
        edit_consumer   => $edit_consumer,
        view_u          => $view_u,
        consumer        => $token,
        save_error      => $save_error,
    });
}

sub consumer_secret_handler {
    my $consumer_id = $_[1];

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};

    my $args = $r->get_args;

    my $token = DW::OAuth::Consumer->from_id( $consumer_id );
    return $r->NOT_FOUND
        unless $token;

    my $view_u = $token->owner;
    return $r->NOT_FOUND
        unless $view_u->equals( $u );

    return DW::Template->render_template( 'oauth/admin/consumer_secret.tt', {
        %$rv,
        consumer        => $token,
    });
}

sub consumer_reissue_handler {
    my $consumer_id = $_[1];

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};

    my $args = $r->get_args;

    my $token = DW::OAuth::Consumer->from_id( $consumer_id );
    return $r->NOT_FOUND
        unless $token;

    my $view_u = $token->owner;
    return $r->NOT_FOUND
        unless $view_u->equals( $u );

    my $done = 0;
    if ( $r->did_post ) {
        $done = 1;
        $token->reissue_token_pair;
    }

    return DW::Template->render_template( 'oauth/admin/consumer_reissue.tt', {
        %$rv,
        consumer        => $token,
        done            => $done,
    });
}

sub consumer_delete_handler {
    my $consumer_id = $_[1];

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};

    my $args = $r->get_args;

    my $token = DW::OAuth::Consumer->from_id( $consumer_id );
    return $r->NOT_FOUND
        unless $token;

    my $view_u = $token->owner;
    return $r->NOT_FOUND
        unless $view_u->equals( $u );

    if ( $r->did_post ) {
        $token->delete;
        return $r->redirect("/admin/oauth");
    }

    return DW::Template->render_template( 'oauth/admin/consumer_delete.tt', {
        %$rv,
        consumer        => $token,
    });
}

sub consumer_create_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};
    my $can_create = DW::OAuth->can_create_consumer( $u );

    return DW::Template->render_template( 'oauth/admin/consumer_create.tt', {
        %$rv,
        can_create      => $can_create,
    }) unless $r->did_post && $can_create;

    my $args = $r->post_args;

    my $name = $args->{name};
    my $website = $args->{website};
    my $uri = URI->new($website);
    my $scheme = $uri->scheme;

    return DW::Template->render_template( 'oauth/admin/consumer_create.tt', {
        %$rv,
        can_create      => $can_create,
        name => $name,
        website => $website,
        error => "Name or website invalid",
    }) unless $name && $scheme =~ m!^https?$!;

    my $token = DW::OAuth::Consumer->new(
        %$rv,
        name => $name,
        website => $website
    );

    return DW::Template->render_template( 'oauth/admin/consumer_secret.tt', {
        %$rv,
        consumer    => $token,
        new         => 1,
    });
}

1;
