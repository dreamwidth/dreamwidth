#!/usr/bin/perl

use strict;
use lib "$ENV{LJHOME}/cgi-bin";

use LJ::SMS::Message;

require "ljlib.pl";

my ($user, $msg) = @ARGV[0,1];

my $u = LJ::load_user($user);

my $ljmsg = LJ::SMS::Message->new
    ( owner     => $u,
      from      => $u, 
      type      => 'incoming',
      body_text => $msg,
      );

warn LJ::D($ljmsg);

warn "Enqueue\n";
LJ::SMS->enqueue_as_incoming($ljmsg);



