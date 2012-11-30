# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

if ($LJ::IS_DEV_SERVER) {
    plan 'no_plan';
} else {
    plan skip_all => "not a developer machine";
    exit 0;
}

my $clustered = ( scalar @LJ::CLUSTERS < 2 ) ? 0 : 1;

my $u = LJ::load_user("system");
ok( $u, "loaded system user" );

if ( $clustered ) {  # don't complain about nonclustered dev setups
    ok( $clustered, "have 2 or more clusters" );
    ok(scalar keys %LJ::DBINFO >= 3, "have 3 or more dbinfo config sections");
}

{
    my %have = ();
    foreach my $dbname (map { $_->{dbname} || 'livejournal' } values %LJ::DBINFO) {
        $have{$dbname}++;
    }
    ok(! scalar(grep { $_ != 1 } values %have), "non-unique databases in config");
}

my %seen_db;
while (my ($n, $inf) = each %LJ::DBINFO) {
    if ($n eq "master") {
        ok(1, "have a master section");
        next unless $clustered;
        my $user_on_master = 0;
        foreach my $cid (@LJ::CLUSTERS) {
            $user_on_master = 1 if
                $inf->{role}{"cluster$cid"};
        }
        ok(!$user_on_master, "you don't have a cluster configured on a master");
    }
}
