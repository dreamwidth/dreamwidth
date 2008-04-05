# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

my $u = temp_user();
ok($u, "got a user");

my $entry = $u->t_post_fake_entry;
ok($entry, "got entry");
my $c1 = $entry->t_enter_comment;
ok($c1, "got comment");
my $c2 = $c1->t_reply;
ok($c2, "got reply comment");

1;

