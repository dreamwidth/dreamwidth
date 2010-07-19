# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";

#plan tests => ;
plan skip_all => 'Fix this test!';

require 'modperl.pl';
use LJ::Test;



my $fa = fake_apache();
ok($fa, "got a fake apache");
ok($LJ::DOMAIN_WEB, "got a web domain");
diag($LJ::DOMAIN_WEB);

my $req = $fa->new_request(
                           uri => "/dev/t_00.bml",
                           headers => {
                               host => $LJ::DOMAIN_WEB,
                           },

#                             uri => "/profile",
#                             args => "mode=full",
#                             headers => {
#                                 host => "brad.lj.bradfitz.com",
#                             },

                           );
ok($req, "got a request");

$fa->run($req);

ok(1);
