# t/console-sysban.t
#
# Test LJ::Console sysban_add command.
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

use Test::More tests => 20;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::Console;
use LJ::Test qw (temp_user with_fake_memcache);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

my $do_ban = sub {

    # this increments the test count by 1
    my $cmd = $_[0];
    my $msg = $run->($cmd);
    my ( $text, $banid ) = split( "#", $msg );
    is( $text, "success: Successfully created ban ", "Successfully created sysban" );

    # must wait: sysban_check compares bandate to NOW();
    sleep 2;
    return $banid;
};

# -- SYSBAN ADD --

my $test_ip           = '500.500.500.500';
my $test_domain2      = 'dw.bogus';
my $test_domain3      = 'dw.totally.bogus';
my $test_domain_bogus = 'totally.bogus';

is(
    $run->("sysban_add talk_ip_test $test_ip 7 testing"),
    "error: You are not authorized to run this command."
);

$u->grant_priv( "sysban", "talk_ip_test" );

ok( !LJ::sysban_check( "talk_ip_test", $test_ip ), "Not currently sysbanned" );

my $banid_talk_ip_test = $do_ban->("sysban_add talk_ip_test $test_ip 7 testing");

ok( LJ::sysban_check( "talk_ip_test", $test_ip ), "Successfully sysbanned test_ip" );

is( $run->("sysban_add talk_ip_test not-an-ip-address 7 testing"),
    "error: Format: xxx.xxx.xxx.xxx (ip address)" );

is( $run->("sysban_add ip $test_ip 7 testing"), "error: You cannot create these ban types" );

# test email addresses for banned domains
$u->grant_priv( "sysban", "email_domain" );

my $banid_email_domain2 = $do_ban->("sysban_add email_domain $test_domain2 7 testing");

ok( LJ::sysban_check( "email_domain", $test_domain2 ), "Successfully sysbanned test_domain2" );

ok(
    LJ::sysban_check( "email", "user\@$test_domain2" ),
    "Successfully sysbanned user\@test_domain2"
);

my $banid_email_domain3 = $do_ban->("sysban_add email_domain $test_domain3 7 testing");

ok( LJ::sysban_check( "email_domain", $test_domain3 ), "Successfully sysbanned test_domain3" );

ok(
    LJ::sysban_check( "email", "user\@$test_domain3" ),
    "Successfully sysbanned user\@test_domain3"
);

ok(
    !LJ::sysban_check( "email_domain", $test_domain_bogus ),
    "Make sure only the three-element subdomain is banned"
);

ok(
    !LJ::sysban_check( "email", "user\@$test_domain_bogus" ),
    "Make sure only the three-element subdomain is banned for user"
);

# cleanup
my $dbh = LJ::get_db_writer();
$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_talk_ip_test );
$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_email_domain2 );
$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_email_domain3 );

# one last check to make sure we are checking domains properly -
# all subdomains of a banned domain should be rejected as well
my $banid_domain_bogus = $do_ban->("sysban_add email_domain $test_domain_bogus 7 testing");

ok( !LJ::sysban_check( "email_domain", $test_domain3 ), "No more sysban for test_domain3" );

ok(
    LJ::sysban_check( "email", "user\@$test_domain3" ),
    "Still sysbanned user\@test_domain3 using test_domain_bogus"
);

$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_domain_bogus );

my $ipv6          = '2001:db8:abcd::1';
my $expanded_ipv6 = '2001:0DB8:ABCD:0000:0000:0000:0000:0001';

subtest 'Console adds and finds an individual IPv6 ban' => sub {
    my $result = $run->("sysban_add talk_ip_test $expanded_ipv6 7 testing");
    like( $result, qr/^success: .*#\d+/, 'Console accepts an expanded IPv6 address' );
    my ($banid) = $result =~ /#(\d+)/;
    return unless $banid;

    my $duplicate = $run->("sysban_add talk_ip_test $ipv6 7 testing");
    like(
        $duplicate,
        qr/^error: .*already banned/,
        'Console rejects an equivalent duplicate as soon as the first ban is created'
    );
    if ( my ($duplicate_id) = $duplicate =~ /#(\d+)/ ) {
        $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $duplicate_id );
    }

    $dbh->do( 'UPDATE sysban SET bandate = NOW() - INTERVAL 1 SECOND WHERE banid = ?',
        undef, $banid );
    is( $dbh->selectrow_array( 'SELECT value FROM sysban WHERE banid = ?', undef, $banid ),
        $ipv6, 'Database stores the canonical address' );
    ok( LJ::sysban_check( 'talk_ip_test', $ipv6 ), 'Compressed spelling is banned' );
    local $LJ::_T_FAKE_IP = $expanded_ipv6;
    ok(
        LJ::sysban_check( 'talk_ip_test', LJ::get_remote_ip() ),
        'The expanded spelling returned by the request IP helper is banned'
    );
    ok( !LJ::sysban_check( 'talk_ip_test', '2001:db8:abcd::2' ), 'Neighbor is not banned' );
    my $matches = LJ::Sysban::populate_full_by_value( $expanded_ipv6, 'talk_ip_test', 'email' );
    is( $matches->{talk_ip_test}[0]{banid},
        $banid, 'Admin lookup finds the ban by either spelling' );

    $dbh->do( 'UPDATE sysban SET value = ? WHERE banid = ?', undef, $expanded_ipv6, $banid );
    ok( LJ::sysban_check( 'talk_ip_test', $ipv6 ), 'An older unnormalized ban still applies' );

    $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $banid );
};

subtest 'IP ban checks use the same IPv6 address identity' => sub {
    local $LJ::IP_BANNED_LOADED        = 0;
    local $LJ::NOANON_IP_BANNED_LOADED = 0;
    local %LJ::IP_BANNED;
    local %LJ::NOANON_IP_BANNED;

    with_fake_memcache {
        for my $type (qw(ip noanon_ip)) {
            ok( !LJ::sysban_check( $type, $ipv6 ), "$type starts without a ban" );
            my $banid = LJ::Sysban::create( what => $type, value => $expanded_ipv6, bandays => 0 );
            $dbh->do( 'UPDATE sysban SET bandate = NOW() - INTERVAL 1 SECOND WHERE banid = ?',
                undef, $banid );

            ok( LJ::sysban_check( $type, $ipv6 ),          "$type matches with a cold cache" );
            ok( LJ::sysban_check( $type, $expanded_ipv6 ), "$type matches with a warm cache" );

            $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $banid );
        }

        LJ::Sysban::tempban_create( ip => $expanded_ipv6, 60 );
        ok(
            LJ::Sysban::tempban_check( ip => [ '2001:db8:abcd::2', $ipv6 ] ),
            'Temporary IP ban matches the compressed spelling in a list of addresses'
        );
    };
};

subtest 'Invalid and protected IPv6 addresses are refused' => sub {
    foreach my $invalid ( '2001:db8::g', '2001:db8::/64', 'fe80::1%eth0' ) {
        like( $run->("sysban_add talk_ip_test $invalid 7 testing"),
            qr/^error:/, "Rejects $invalid as an individual address" );
    }

    local %LJ::UNBANNABLE_IPS = ( '^127\.' => 'local IPv4', '^::1$' => 'local IPv6' );
    like(
        $run->('sysban_add talk_ip_test 127.0.0.1 7 testing'),
        qr/^error: Cannot ban IP/,
        'Existing IPv4 protection still applies'
    );
    like(
        $run->('sysban_add talk_ip_test 0:0:0:0:0:0:0:1 7 testing'),
        qr/^error: Cannot ban IP/,
        'Expanded IPv6 spelling cannot bypass a canonical protection rule'
    );
    like(
        $run->('sysban_add talk_ip_test ::ffff:7f00:1 7 testing'),
        qr/^error: Cannot ban IP/,
        'IPv4-mapped IPv6 cannot bypass IPv4 protection'
    );
};
