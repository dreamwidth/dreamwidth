# t/notificationmethod-email.t
#
# Test LJ::NotificationMethod::Email
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 69;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user memcache_stress);

use LJ::NotificationMethod::Email;
use LJ::Event::AddedToCircle;

my $u;
my $valid_u = sub {
    return $u = temp_user();
};

sub LJ::send_mail {
    my $opts = shift
        or die "No opts";

    my $email = qq {
      To: $opts->{to}
      From: $opts->{from} ($opts->{fromname})
      Subject: $opts->{subject}
      HTML Body: "$opts->{html}"
      Plaintext Body: "$opts->{body}"
      };

    # check for correct fields
    is($opts->{to}, $u->email_raw, "Email address");
    is($opts->{from}, $LJ::BOGUS_EMAIL, "From address");
    like($opts->{body}, qr/.+ has subscribed to you/i, "Body");

    return 1;
}

# less duplication of this so we can revalidate
my $meth;
my $valid_meth = sub {
    $meth = eval { LJ::NotificationMethod::Email->new($u) };
    ok(ref $meth && ! $@, "valid Email method instantiated");
    return $meth;
};

sub run_tests{
    {
        # constructor tests
        $valid_u->();
        $valid_meth->();

        $meth = eval { LJ::NotificationMethod::Email->new() };
        like($@, qr/no args/, "no args passed to constructor");

        $meth = eval { LJ::NotificationMethod::Email->new({user => 'ugly'}) };
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
        $valid_meth->();

        my $ev;

        my $fromu = $u; # yeah, you can watch yourself
        $ev = LJ::Event::AddedToCircle->new( $u, $fromu, 2 );
        ok(ref $ev && ! $@, "created LJ::Event::AddedToCircle object");

        # failures
        eval { LJ::NotificationMethod::Email::notify() };
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
