#!/usr/bin/perl
#
# DW::Controller::MemcacheClear
#
# Clear memcache for a user
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::MemcacheClear;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;

use LJ::User;
use LJ::Userpic;

DW::Routing->register_string( "/admin/memcache_clear", \&index_controller );
DW::Controller::Admin->register_admin_page(
    '/',
    path     => 'memcache_clear',
    ml_scope => '/admin/memcache_clear.tt',
    privs    => ['siteadmin:memcacheclear']
);

my %clear = (
    all => {
        order  => -1,
        action => sub { LJ::wipe_major_memcache( $_[0] ); },
    },
    userpic => {
        action => sub { LJ::Userpic->delete_cache( $_[0] ); },
    }
);

map {
    $clear{$_}->{key}     = $_;
    $clear{$_}->{name_ml} = ".purge.$_";
} keys %clear;

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => ["siteadmin:memcacheclear"] );
    return $rv unless $ok;

    my $r    = DW::Request->get;
    my $args = $r->did_post ? $r->post_args : $r->get_args;

    my $vars = {
        %$rv,

        # so the controller looking up the ML strings does not pollute our hash.
        clear_options => [
            map {
                { %$_ }
            } values %clear
        ],
    };

    if ( $r->method eq 'POST' ) {
        eval {
            die "Invalid form auth" unless LJ::check_form_auth( $args->{lj_form_auth} );

            my $u = LJ::load_user( $args->{username} );
            die "Invalid username" unless $u;

            my $what = $clear{ $args->{what} || 'all' };
            die "Invalid key" unless $what;

            $what->{action}->($u);
            $vars->{cleared} = 1;
        };
        if ($@) {
            $vars->{error} = $@;
        }
    }

    return DW::Template->render_template( 'admin/memcache_clear.tt', $vars );
}

1;
