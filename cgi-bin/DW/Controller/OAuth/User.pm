#!/usr/bin/perl
#
# DW::Controller::OAuth::User
#
# Web-facing OAuth ( User Methods )
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
package DW::Controller::OAuth::User;

use strict;
use warnings;
use DW::Routing;
use DW::Controller;
use DW::Request;

use DW::OAuth::Consumer;
use DW::OAuth::Access;

# User facing
DW::Routing->register_string( "/oauth/index", \&index_handler, app => 1 );
DW::Routing->register_regex( qr!^/oauth/token/(\d+)$!,             \&token_handler,  app => 1 );
DW::Routing->register_regex( qr!^/oauth/token/(\d+)/deauthorize$!, \&delete_handler, app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $args = $r->get_args;

    my $u      = $rv->{u};
    my $view_u = $u;

    my $view_other = DW::OAuth->can_view_other($u);
    $view_u = LJ::load_user( $args->{user} )
        if ( $view_other && $args->{user} );
    my $tokens = DW::OAuth::Access->tokens_for_user($view_u);
    DW::OAuth::Access->load_all_lastaccess($tokens);

    $tokens = [ sort { $b->lastaccess <=> $a->lastaccess } @$tokens ];

    return DW::Template->render_template(
        'oauth/index.tt',
        {
            %$rv,
            viewother      => !$u->equals($view_u),
            view_u         => $view_u,
            tokens         => $tokens,
            can_view_other => $view_other,
        }
    );
}

sub token_handler {
    my $consumer_id = $_[1];

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $u    = $rv->{u};
    my $args = $r->get_args;

    my $view_u = $u;

    my $view_other = DW::OAuth->can_view_other($u);
    $view_u = LJ::load_user( $args->{user} )
        if ( $view_other && $args->{user} );
    my $token = DW::OAuth::Access->from_consumer( $view_u, $consumer_id );
    return $r->NOT_FOUND
        unless $token;

    return DW::Template->render_template(
        'oauth/token.tt',
        {
            %$rv,
            viewother     => !$u->equals($view_u),
            view_consumer => $view_other || $token->consumer->owner->equals($u),
            view_u        => $view_u,
            token         => $token,
        }
    );
}

sub delete_handler {
    my $consumer_id = $_[1];

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};

    my $redir_dest = LJ::create_url( "/oauth/token/$consumer_id", keep_args => qw/ user / );

    return $r->redirect($redir_dest)
        unless $r->did_post;

    my $token = DW::OAuth::Access->from_consumer( $u, $consumer_id );

    return $r->NOT_FOUND
        unless $token;

    return $r->redirect($redir_dest)
        unless $token->user->equals($u);

    $token->delete if $token;
    return $r->redirect("/oauth/");
}

1;

