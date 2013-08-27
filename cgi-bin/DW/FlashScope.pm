#!/usr/bin/perl
#
# DW::FlashScope
#
# Controls storing parameters temporarily in memcache for redirects.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::FlashScope;
use strict;
use warnings;

use Storable;

my $fs_id_arg = "dw_fs";

# redirects the request if flash scope is available.  if not, returns
# an internal redirect to the given page.
sub flash_redirect {
    my ( $class, $request, $uri, $vars ) = @_;

    # freeze the frozen vars
    my $frozen = Storable::nfreeze( $vars );
    my $remote = LJ::get_remote();
    # we can only do a flash scope redirect if we have a user.  in theory
    # we could do it without a remote, but then we'd need a better guid
    # algorithm for the key
    if ( $remote ) {
        my $flashkey = $class->create_flashkey();
        my $memkey = $class->create_memkey( $flashkey );
        my $set_value = $remote->memc_set( $memkey => $frozen, 300 );
        if ( $set_value ) {
            # if we successfully set the value in memcache, then redirect
            # with the flash key
            my $redir_url =  LJ::create_url( $uri, host => $LJ::DOMAIN_WEB, args => { $fs_id_arg, $flashkey } );
            return $request->redirect( $redir_url );
        }
    }

    # memcache isn't available, so just do an internal redirect instead
    LJ::start_request();
    $request->note( 'internal_redir', $uri );
    $request->pnote( 'flash_vars', $frozen );
    my $redir_handler = DW::Routing->call( uri => $uri, role => 'app', format => 'html' );
    return $request->DECLINED;
}

# returns flash-scoped variables for the request. gets the values either from
# the request (if an internal redirect was done) or memcache (if a proper
# redirect was done)
sub flash_vars {
    my ( $class, $request ) = @_;
    my $frozen;
    # the pnote should only be set if an internal redirect was done
    if ( $request->pnote( 'flash_vars' ) ) {
        $frozen = $request->pnote( 'flash_vars' );
    } else {
        # try getting the value from memcache
        my $remote = LJ::get_remote();
        if ( $remote ) {
            my $flashkey = $request->get_args->{$fs_id_arg};
            my $memkey = $class->create_memkey( $flashkey );
            $frozen = $remote->memc_get( $memkey );
            $remote->memc_delete( $memkey );
        }
    }
    return Storable::thaw( $frozen );
}

# creates a key we can use to save and recover the flash scope
sub create_flashkey {
    # FIXME we can do better than this.  need a real unique id
    return time();
}

# makes the actual key we use in memcache
sub create_memkey {
    my ( $class, $flashkey ) = @_;
    return "flash:" . $flashkey;
}
1;

