#!/usr/bin/perl
#
# t/bin/routing-table-helper.pl
#
# Test to make sure the routing table is non-empty
# This must stay in it's own file, do not merge this back into t/routing-table.t
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use DW::Routing;

my $ct = scalar keys %DW::Routing::string_choices;

$ct += scalar @$_ foreach values %DW::Routing::regex_choices;

isnt( $ct, 0, "routing table empty" );

# test some known lookups!

ok( defined DW::Routing->get_call_opts( uri => "/nav",         app => 1 ) );
ok( defined DW::Routing->get_call_opts( uri => "/nav/read",    app => 1 ) );
ok( defined DW::Routing->get_call_opts( uri => "/admin",       app => 1 ) );
ok( defined DW::Routing->get_call_opts( uri => "/admin/",      app => 1 ) );
ok( defined DW::Routing->get_call_opts( uri => "/admin/index", app => 1 ) );

1;
