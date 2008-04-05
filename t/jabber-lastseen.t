#!/usr/bin/perl
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use Carp;

$SIG{__DIE__} = sub { Carp::croak( @_ ) };

use LJ::Jabber::LastSeen;
use LJ::Test qw(temp_user memcache_stress);

unless ($ENV{TEST_TODO}) {
    plan skip_all => "This test is disabled until Jabber::LastSeen is rewritten";
    exit;
}

plan 'no_plan';

memcache_stress( sub {

my $one = {
    u => temp_user(),
    presence => "<xml><data>",
    motd_ver => 3,
};

my $two = {
    u => temp_user(),
    presence => "<more><xml>",
    motd_ver => 5,
};

add( $one );
load( $one );

add( $two );
load( $two );
load( $one );

} );

sub add {
    my $args = shift;
    my $obj = LJ::Jabber::LastSeen->create( %$args );

    ok( $obj, "Object create" );
    checkattrs( $obj, $args );

    return $obj;
}

sub load {
    my $args = shift;
    my $obj = LJ::Jabber::LastSeen->new( $args->{u} );

    ok( $obj, "Object load" );
    checkattrs( $obj, $args );

    return $obj;
}

sub checkattrs {
    my $obj = shift;
    my $check = shift;
    is( $obj->u, $check->{u}, "User matches" );
    is( $obj->presence, $check->{presence}, "presence data matches" );
    is( $obj->motd_ver, $check->{motd_ver}, "motd_ver matches" );
}
