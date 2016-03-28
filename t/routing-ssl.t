# t/routing-ssl.t
#
# Routing tests: Smart SSL redirect
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; };
use DW::Routing::Test tests => 5;

$DW::Routing::T_TESTING_ERRORS = 1;

expected_format('html');

begin_tests();

DW::Routing->register_string( "/ssl_test", sub { return -100; }, app => 1, user => 1, prefer_ssl => 1, args => "maybe" );

$LJ::IS_SSL = 0;
$LJ::USE_SSL = 1;

handle_custom("/ssl_test",name => "ssl possible, not ssl", final => sub {
    my ( $r, $rv ) = @_;
    plan( tests => 2 );
    is( $rv, $r->REDIRECT );
    is( $r->header_out( 'Location' ), "https://www.example.com/ssl_test" );
});

handle_custom("/ssl_test",name => "ssl possible, not ssl, POST", method=>"POST", final => sub {
    my ( $r, $rv ) = @_;
    plan( tests => 1 );
    is( $rv, -100 );
});

handle_custom("/ssl_test", name => "ssl possible, on ssl", opts=>{ ssl => 1 }, final => sub {
    my ( $r, $rv ) = @_;
    plan( tests => 1 );
    is( $rv, -100 );
});

handle_custom("/ssl_test",name => "ssl possible, not ssl, user page", opts=>{username=>'example'}, final => sub {
    my ( $r, $rv ) = @_;
    plan( tests => 1 );
    is( $rv, $r->REDIRECT );
});

$LJ::USE_SSL = 0;

handle_custom("/ssl_test",name => "no ssl possible", final => sub {
    my ( $r, $rv ) = @_;
    plan( tests => 1 );
    is( $rv, -100 );
});


