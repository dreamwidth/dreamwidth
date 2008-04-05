# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

my $u = LJ::load_user("system");
ok($u);

{
    local %LJ::CAP = ();
    is(LJ::class_bit("underage"), undef, "no class bit");
    eval { $u->in_class("non_exist") };
    like($@, qr/unknown class/i, "checking in_class on bogus class dies");
    is($u->in_class("underage"), 0, "checking in_class on underage doesn't fail");
}

# make this test work on general or policyconfig'ed sites
unless (LJ::class_bit("underage")) {
    $LJ::CAP{15} = { '_key' => 'underage' };
}

ok(LJ::class_bit("underage"), "got the class bit");
ok($u->underage(0));
ok(! $u->underage);
ok($u->underage(1));
ok($u->underage);
ok($u->underage_status("C"));  # set due to cookie
is($u->underage_status, "C", "still set to cookie");

{
    local %LJ::CAP = ();
    ok(! $u->underage, "no longer underage, feature disabled");
    is($u->underage_status, undef, "status gone");
}


