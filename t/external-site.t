# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::ExternalSite::Vox;

my $vox = LJ::ExternalSite::Vox->new;
ok($vox);

ok(! $vox->matches_url("http://bradfitz.com"), "not non-vox");
ok(! $vox->matches_url("http://-blah.vox.com"), "not -blah");
ok(! $vox->matches_url("http://8user.vox.com"), "not start numeric");
ok($vox->matches_url("http://a-b.vox.com"), "a-b");
ok(! $vox->matches_url("http://a_b.vox.com"), "not underscores");
is($vox->matches_url("A-B.VOX.COM"), "http://a-b.vox.com/");
is($vox->matches_url("http://A-B.VOX.COM"), "http://a-b.vox.com/");
is($vox->matches_url("http://A-B.VOX.COM/"), "http://a-b.vox.com/");

{
    local @LJ::EXTERNAL_SITES = (
                                 ["Vox", "vox.com"],
                                 );
    LJ::ExternalSite->forget_site_objs;
    my @sites = LJ::ExternalSite->sites;
    is(scalar @sites, 1, "got 1 object");
    is(ref $sites[0], "LJ::ExternalSite::Vox", "is vox");
}

1;

