#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw(temp_user memcache_stress);

use Class::Autouse qw(
                      LJ::Event::Befriended
                      LJ::NotificationMethod::SMS
                      );

local $LJ::_T_NO_SMS_QUOTA = 1;

my $u;
my $valid_u = sub {
    return $u = temp_user();
};

# less duplication of this so we can revalidate
my $meth;
my $valid_meth = sub {
    $meth = eval { LJ::NotificationMethod::SMS->new($u) };
    ok(ref $meth && ! $@, "valid SMS method instantiated");
    return $meth;
};

sub run_tests{
    {
        # constructor tests
        $valid_u->();
        $valid_meth->();

        $meth = eval { LJ::NotificationMethod::SMS->new() };
        like($@, qr/invalid user/, "no args passed to constructor");

        $meth = eval { LJ::NotificationMethod::SMS->new({user => 'ugly'}) };
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

        $mu = eval { $meth->u };
        is_deeply($mu, $u, "gotten u is constructed u");

        $mu = eval { $meth->u('foo') };
        like($@, qr/invalid 'u'/, "setting non-ref");

        $mu = eval { $meth->u($u, 'bar') };
        like($@, qr/superfluous/, "superfluous args");

        # clear out $u
        %$u = ();
        LJ::start_request();
        $mu = eval { $meth->u };
        ok(! %$u, "cleared 'u'");

        $valid_u->();

        $mu = eval { $meth->u($u) };
        is_deeply($mu, $u, "set new 'u' in object");
    }

    # notify
    {
        $valid_u->();
        $u->set_sms_number("+12345", verified => 'Y');
        $valid_meth->();

        my $ev;

        my $fromu = $u; # yeah, you can friend yourself
        $ev = LJ::Event::Befriended->new($u, $fromu);
        ok(ref $ev && ! $@, "created LJ::Event::Befriended object");

        # failures
        eval { LJ::NotificationMethod::SMS::notify() };
        like($@, qr/'notify'.+?object method/, "notify class method");

        eval { $meth->notify };
        like($@, qr/requires an event/, "notify no events");

        eval { $meth->notify(undef) };
        like($@, qr/invalid event/, "notify undef event");

        my $str = $ev->as_string;

        my $got_sms = 0;
        local $LJ::_T_SMS_SEND = sub {
            my $sms = shift;
            $got_sms = $sms;
        };

        $meth->notify($ev);
        ok($got_sms, "got sms");
    }
}

memcache_stress {
    run_tests;
}
