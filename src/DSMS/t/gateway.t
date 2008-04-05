#!/usr/bin/perl

{
    use strict;
    use Test::More 'no_plan';

    use lib "./lib";
    use DSMS::Gateway;

    my $gate;
    
    # invalid parameter cases
    $gate = eval { DSMS::Gateway->new(1) };
    like($@, qr/invalid parameters/, "wrong parameter format");

    $gate = eval { DSMS::Gateway->new( foo => 'bar' ) };
    like($@, qr/invalid parameters/, "invalid option");

    # valid cases
    $gate = eval { DSMS::Gateway->new };
    ok($gate && ! $@, "no arguments");

    $gate = eval { DSMS::Gateway->new( config => {} ) };
    ok($gate && ! $@, "empty config hashref");

    $gate = eval { DSMS::Gateway->new( config => undef ) };
    ok($gate && ! $@, "undef config");

    $gate = eval { DSMS::Gateway->new( config => "blob" ) };
    ok($gate && ! $@, "blob config");
}
