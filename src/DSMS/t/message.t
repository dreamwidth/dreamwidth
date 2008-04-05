#!/usr/bin/perl

{
    use strict;
    use Test::More 'no_plan';

    use lib "./lib";
    use DSMS::Message;

    my $msg;
    
    # invalid parameters
    $msg = eval { DSMS::Message->new( foo => "bar" ) };
    like($@, qr/invalid parameters/, "invalid parameters");

    # invalid recipients cases
    $msg = eval { DSMS::Message->new };
    like($@, qr/no .+ specified/, "no arguments");

    $msg = eval { DSMS::Message->new( from => '123', to => '+1234567890' ) };
    like($@, qr/invalid recipient/, "invalid from");

    $msg = eval { DSMS::Message->new( from => '12345', to => undef ) };
    like($@, qr/no recipient/, "undef recipients");

    $msg = eval { DSMS::Message->new( from => '12345', to => 'foo' ) };
    like($@, qr/invalid recipient/, "invalid single recipient");

    $msg = eval { DSMS::Message->new( from => '12345', to => [ 'foo' ] ) };
    like($@, qr/invalid recipient/, "invalid single recipient in array");

    $msg = eval { DSMS::Message->new( from => '12345', to => [ ] ) };
    like($@, qr/empty recipient/, "empty recipient list");

    $msg = eval { DSMS::Message->new
                      ( from => 12345, 
                        to => [ '+1234567890', '123', '+1234567890' ] ) 
                  };
    like($@, qr/invalid recipient:\s+123/, "invalid recipient in list");


    # valid case
    $msg = eval { DSMS::Message->new( from      => '12345',
                                      to        => '+1234567890',
                                      body_text => '' ) };
    ok(! $@ && $msg->body_text eq '', "empty body text specified");

    $msg = eval { DSMS::Message->new( from      => '12345',
                                      to        => '+1234567890' ) };
    ok(! $@ && $msg->body_text eq '', "from and to w/o body text: \$@=$@, txt=" . $msg->body_text);

    $msg = eval { DSMS::Message->new( from      => '12345', 
                                      to        => '+1234567890', 
                                      body_text => 'TestMsg' ) };
    ok($msg && ! $@, "single number and body");

    $msg = eval { DSMS::Message->new( from      => '12345', 
                                      to        => '+1234567890', 
                                      subject   => 'TestSubj',
                                      body_text => 'TestMsg' ) };
    ok($msg && ! $@, "single number, subject and body");
}
