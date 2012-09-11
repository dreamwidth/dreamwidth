#!/usr/bin/perl
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

use Carp;

$SIG{__DIE__} = sub { Carp::croak( @_ ) };

use LJ::Jabber::Presence;

use LJ::Test qw(temp_user memcache_stress);

my %presence;

memcache_stress( sub {

my $u = temp_user();

checkres( $u, 0 );

my $one = {
    u => $u,
    resource => "Resource",
    cluster => "obj",
    client => "a client",
    presence => "<xml><data>",
};

my $two = {
    u => $u,
    resource => "Another Resource",
    cluster => "bobj",
    client => "another client",
    presence => "<more><xml>",
};

add( $one );
load( $one );

add( $two );
load( $two );
load( $one );

del( $one );
del( $two );

add( $one );
add( $two );

del_all( $u );

add( $one );
load( $one );

add( $two );
load( $one );
load( $two );

delobj( $two );
delobj( $one );

add( $two );
add( $one );

delobj_all( $one );

%presence = ();
} );

sub add {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $args = shift;
    my $obj = LJ::Jabber::Presence->create( %$args );

    subtest "add $args->{resource} - $args->{client}" => sub {
        $presence{$args->{resource}} = 1;
    
        ok( $obj, "Object create" );
        checkattrs( $obj, $args );
        checkres( $args->{u}, scalar( keys %presence ) );
    };

    return $obj;
}

sub load {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $args = shift;
    my $obj = LJ::Jabber::Presence->new( $args->{u}, $args->{resource} );

    subtest "load $args->{resource} - $args->{client}" => sub {
        ok( $obj, "Object load" );
        checkattrs( $obj, $args );
        checkres( $args->{u}, scalar( keys %presence ) );
    };

    return $obj;
}

sub del {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $args = shift;

    subtest "del $args->{resource} - $args->{client}" => sub {
        LJ::Jabber::Presence->delete( $args->{u}->id, $args->{resource} );
    
        delete $presence{$args->{resource}};
    
        checkres( $args->{u}, scalar( keys %presence ) );
    };
}

sub delobj {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $args = shift;
    my $obj = load( $args );

    subtest "delobj $args->{resource} - $args->{client}" => sub {
        delete $presence{$args->{resource}};
        $obj->delete;
    
        checkres( $args->{u}, scalar( keys %presence ) );
    };
}

sub del_all {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $u = shift;

    subtest "delall" => sub {
        LJ::Jabber::Presence->delete_all( $u->id );
    
        %presence = ();
    
        checkres( $u, 0 );
    };
}

sub delobj_all {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $args = shift;
    my $obj = load( $args );

    subtest "delobj_all $args->{resource} - $args->{client}" => sub {
        %presence = ();
        $obj->delete_all;
    
        checkres( $args->{u}, 0 );
    };
}

sub checkattrs {
    my $obj = shift;
    my $check = shift;

    is( $obj->u, $check->{u}, "User matches" );
    is( $obj->resource, $check->{resource}, "Resource matches" );
    is( $obj->cluster, $check->{cluster}, "cluster matches" );
    is( $obj->client, $check->{client}, "client matches" );
    is( $obj->presence, $check->{presence}, "presence data matches" );
}

sub checkres {
    my $u = shift;
    my $correct = shift;

    my $resources = LJ::Jabber::Presence->get_resources( $u->id );
    is( scalar(keys(%$resources)),$correct, "$correct Resources found for user" );
}
