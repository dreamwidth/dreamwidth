#!/usr/bin/perl
#
# DW::Controller::Interface::XMLRPC
#
# This controller is for the old XMLRPC interface
#
# Authors:
#       Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Interface::XMLRPC;

use strict;
use DW::Routing;
use DW::Request::XMLRPCTransport;

DW::Routing->register_string(
    '/interface/xmlrpc', \&interface_handler,
    app     => 1,
    format  => 'xml',
    methods => { POST => 1 }
);

sub interface_handler {
    my $r = DW::Request->get;

    my $server =
        DW::Request::XMLRPCTransport->on_action( sub { die "Access denied\n" if $_[2] =~ /:|\'/ } )
        ->dispatch_to('LJ::XMLRPC')->handle();
    return $r->OK;
}

1;

