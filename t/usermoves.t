# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Event;
use FindBin qw($Bin);

if (@LJ::CLUSTERS < 2) {
    plan skip_all => "Less than two clusters.";
    exit 0;
} else {
    plan tests => 4;
}

my $u = LJ::load_user("system");
ok($u, "got system user");
ok($u->{clusterid}, "on a clusterid ($u->{clusterid})");

my @others = grep { $u->{clusterid} != $_ } @LJ::CLUSTERS;
my $dest = shift @others;

my $rv = system("$ENV{LJHOME}/bin/moveucluster.pl", "--ignorebit", "--destdel", "--verbose=0", "system", $dest);
ok(!$rv, "no errors moving to cluster $dest");

$u = LJ::load_user("system", "force");
is($u->{clusterid}, $dest, "user moved to cluster $dest");



