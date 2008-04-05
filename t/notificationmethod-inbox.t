#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw(temp_user memcache_stress);

use Class::Autouse qw(
                      LJ::Event::Befriended
                      LJ::NotificationMethod::Inbox
                      );

my $u;
my $valid_u = sub {
    return $u = temp_user();
};

# less duplication of this so we can revalidate
my $meth;
my $valid_meth = sub {
    $meth = eval { LJ::NotificationMethod::Inbox->new($u, $u->{userid}) };
    ok(ref $meth && ! $@, "valid Inbox method instantiated");
    return $meth;
};

sub run_tests{
    {
        # constructor tests
        $valid_u->();
        $valid_meth->();

        $meth = eval { LJ::NotificationMethod::Inbox->new() };
        like($@, qr/no args/, "no args passed to constructor");

        $meth = eval { LJ::NotificationMethod::Inbox->new({user => 'ugly'}) };
        like($@, qr/invalid user/, "non-user passed to constructor");

        # test valid case
        $valid_meth->();
    }

    # accessor/setter tests
    {
        my $mu;

        $valid_u->();
        $valid_meth->();

        # now we have valid from prev test
        $mu = eval { $meth->{u} };
        is($mu, $u, "member u is constructed u");

        $mu = eval { $meth->u('foo') };
        like($@, qr/invalid 'u'/, "setting non-ref");

        $mu = eval { $meth->u($u, 'bar') };
        like($@, qr/superfluous/, "superfluous args");

        # clear out $u
        %$u = ();
        LJ::start_request();
        $mu = eval { $meth->u };
        ok(! %$u, "cleared 'u'");
    }

    # notify
    {
        $valid_u->();
        $valid_meth->();

        my $ev;

        my $fromu = $u; # yeah, you can friend yourself
        $ev = LJ::Event::Befriended->new($u, $fromu);
        ok(ref $ev && ! $@, "created LJ::Event::Befriended object");

        # failures
        eval { LJ::NotificationMethod::Inbox::notify() };
        like($@, qr/'notify'.+?object method/, "notify class method");

        eval { $meth->notify };
        like($@, qr/requires one or more/, "notify no events");

        eval { $meth->notify(undef) };
        like($@, qr/invalid event/, "notify undef event");

        eval { $meth->notify($ev, undef, $ev) };
        like($@, qr/invalid event/, "undef event with noise");

        my $str = $ev->as_string;
        $meth->notify($ev);
    }
}

memcache_stress {
    run_tests;
}
