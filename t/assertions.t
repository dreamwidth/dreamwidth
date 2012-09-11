# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

plan tests => 13;

ok(LJ::assert_is("foo", "foo"));
ok(! eval { LJ::assert_is("foo", "bar") });

my $u = LJ::load_user("system");
ok($u->selfassert);
{
    local $u->{userid} = 9999;
    ok(! eval { $u->selfassert });
}
ok($u->selfassert);
{
    local $u->{user} = "systemNOT";
    ok(! eval { $u->selfassert });
}
ok($u->selfassert);
{
    local $u->{user} = "systemNOT";
    eval {
        my $u2 = LJ::DB::require_master( sub { LJ::load_userid($u->{userid}) } );
    };
    like($@, qr/AssertIs/);
}

{
    local $u->{user} = "systemNOT";
    eval {
        my $u2 = LJ::load_userid($u->{userid});
    };
    like($@, qr/AssertIs/);
}

{
    local $u->{userid} = 5555;
    eval {
        my $u2 = LJ::load_user("system");
    };
    like($@, qr/AssertIs/);
}

my $empty;
LJ::load_userids_multiple([ $u->{userid} => \$empty ]);
ok($empty == $u, "load multiple worked");

my $bogus = bless { userid => $u->{userid} + 1 }, 'LJ::User';
ok(! eval { LJ::load_userids_multiple([ $u->{userid} => \$bogus ]) });
like($@, qr/AssertIs/, "failed on blowing away existing user record");
