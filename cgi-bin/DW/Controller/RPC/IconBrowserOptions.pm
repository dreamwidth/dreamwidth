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

sub iconbrowser_save {
    my $r      = DW::Request->get;
    my $post   = $r->post_args;
    my $remote = LJ::get_remote();
    return $r->FORBIDDEN
        unless $remote
        && $remote->session
        && $post->{lj_form_auth}
        && LJ::check_form_auth( $post->{lj_form_auth} );

    my @options = grep { defined $post->{$_} } qw(keywordorder metatext smallicons);
    return $r->HTTP_BAD_REQUEST
        if grep { $post->{$_} ne 'true' && $post->{$_} ne 'false' } @options;

    for my $option (@options) {
        my $setter = "iconbrowser_$option";
        $remote->$setter( $post->{$option} eq 'true' ? 'Y' : 'N' );
    }

    $r->print( to_json( { success => 1 } ) );
    return $r->OK;
}

1;
