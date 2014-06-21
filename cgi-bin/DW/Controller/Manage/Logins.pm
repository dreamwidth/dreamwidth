#!/usr/bin/perl
#
# DW::Controller::Manage::Logins
#
# /manage/logins
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Logins;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/logins", \&login_handler, app => 1 );

sub login_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $u = $rv->{remote};
    my $adminmode = $u && $u->has_priv( 'canview', 'sessions' );
    my $user = LJ::canonical_username( $r->get_args->{user} || $r->post_args->{user} );

    if ( $adminmode && $user ) {
        $u = LJ::load_user($user);
        return error_ml( 'error.username_notfound' ) unless $u;
        $user = undef if $rv->{remote}->equals( $u );
    } else {
        $user = undef;
    }

    my $sessions = $u->sessions;
    my $session = $u->session;

    if ( $r->did_post ) {
        # Form auth is automagically checked.
        if ( ! $user ) {
            my $sid = $r->post_args->{session};
            $sessions->{$sid}->destroy if $sessions->{$sid};
        }
        return $r->redirect( LJ::create_url(undef) );
    }
    my $sth = $u->prepare("SELECT logintime, sessid, ip, ua FROM loginlog WHERE userid=?")
        or die('Unable to prepare loginlog');
    $sth->execute($u->userid)
        or die('Unable to execute loginlog query');
    my $logins = $sth->fetchall_arrayref
        or die('Unable to fetch loginlog');

    my ( @login_data, @prior_data );
    foreach my $login (sort { $a->[1] <=> $b->[1] } @$logins) {
        my $sid = $login->[1];
        my $data = {
            time => LJ::time_to_http($login->[0]),
            sid => $sid,
            ip => $login->[2],
            useragent => $login->[3],
        };
        if (defined $sessions->{$sid}) {
            $data->{current} = ( $session && ($session->id == $sid) ) ? 1 : 0;
            if ( $adminmode ) {
                my $s_data = $sessions->{$sid};
                $data->{exptype} = $s_data->exptype;
                $data->{bound} = $s_data->ipfixed || '-';
                $data->{create} = LJ::time_to_http($s_data->{$sid}->{timecreate});
                $data->{expire} = LJ::time_to_http($s_data->{$sid}->{timeexpire});
            }
            push @login_data, $data;
        } else {
            push @prior_data, $data;
        }
    }

    my $oauth_tokens = DW::OAuth::Access->tokens_for_user( $u );

    my @oauth_data;

    if ( scalar @$oauth_tokens ) {
        DW::OAuth::Access->load_all_lastaccess( $oauth_tokens );
        my $time_threshold = time() - 86400; # 24 hours
        foreach my $token ( sort { $b->lastaccess <=> $a->lastaccess } grep { $_->lastaccess >= $time_threshold } @$oauth_tokens ) {
            push @oauth_data, {
                id   => $token->consumer->id,
                name => $token->consumer->name,
                time => LJ::time_to_http($token->lastaccess),
            };
        }
    }

    my $vars = {
        %$rv,
        loggedin => \@login_data,
        prior => \@prior_data,

        has_any_oauth => scalar( @$oauth_tokens ) ? 1 : 0,
        oauth => \@oauth_data,

        adminmode => $adminmode ? 1 : 0,
        user => $user,
    };

    return DW::Template->render_template( 'manage/logins.tt', $vars );
}

1;
