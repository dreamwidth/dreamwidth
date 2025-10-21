#!/usr/bin/perl
#
# DW::Controller::RPC::IconBrowserOptions
#
# Remember options for the icon browser
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2012-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::RPC::IconBrowserOptions;

use strict;
use DW::Routing;
use LJ::JSON;

DW::Routing->register_rpc( "iconbrowser_save", \&iconbrowser_save, format => 'json' );

# saves the metatext / smallicons options (Y/N)
sub iconbrowser_save {

    # gets the request and args
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    my $remote = LJ::get_remote();

    if ( $post->{metatext} ) {
        $remote->iconbrowser_metatext( $post->{metatext} eq "true" ? "Y" : "N" );
    }

    if ( $post->{smallicons} ) {
        $remote->iconbrowser_smallicons( $post->{smallicons} eq "true" ? "Y" : "N" );
    }

    $r->print( to_json( { success => 1 } ) );
    return $r->OK;
}

1;
