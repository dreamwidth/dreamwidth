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

use Test::More tests => 19;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

subtest 'protected IPs' => sub {
    local %LJ::UNBANNABLE_IPS = ( qr/\A192\.0\.2\.(?:10|11)\z/ => 'Office & support' );
    my $opts = { skipexisting => 1 };

    for my $bantype (qw(ip noanon_ip talk_ip_test)) {
        for my $ip (qw(192.0.2.10 192.0.2.10 192.0.2.11)) {
            like(
                LJ::Sysban::validate( $bantype, $ip, $opts ),
                qr/Cannot ban IP .*Office &amp; support/,
                "$bantype refuses protected IP $ip on every attempt"
            );
        }
        like(
            LJ::Sysban::validate( $bantype, "192.0.2.10\n", $opts ),
            qr/Format: xxx\.xxx\.xxx\.xxx/,
            "$bantype rejects trailing-newline IP before protected check"
        );
        ok(
            !LJ::Sysban::validate( $bantype, '192.0.2.100', $opts ),
            "$bantype allows an IP outside the protected pattern"
        );
    }
};

subtest 'spamreports trimmed protected IP' => sub {
    require DW::Controller::Admin::SpamReports;
    require DW::Request::Standard;
    require HTTP::Request;

    local %LJ::UNBANNABLE_IPS = ( qr/\A192\.0\.2\.12\z/ => 'Office IP' );
    my $admin = temp_user();
    $admin->grant_priv( 'siteadmin', 'spamreports' );
    $admin->grant_priv( 'sysban',    'talk_ip_test' );
    LJ::set_remote($admin);

    my $run_del = sub {
        my ($encoded_ip) = @_;
        my $auth = LJ::eurl( LJ::form_auth(1) );
        my $body = "lj_form_auth=$auth&mode=del&srids=0&sysban_ip=$encoded_ip&sysban_note=test";
        my $req  = HTTP::Request->new( POST => 'http://www.dreamwidth.org/admin/spamreports' );
        $req->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
        $req->content($body);

        DW::Request::reset();
        my $r = DW::Request::Standard->new($req);
        local $DW::Request::cur_req = $r;
        DW::Controller::Admin::SpamReports::main_controller();
        return $r;
    };

    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM sysban WHERE what = 'talk_ip_test' AND value IN (?, ?)",
        undef, '192.0.2.12', '192.0.2.99' );

    my $r_protected = $run_del->('192.0.2.12%0A');
    is( $r_protected->status, 200, 'spam report closure with padded protected IP succeeds' );
    my ($protected_count) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM sysban WHERE what = 'talk_ip_test' AND value = ?",
        undef, '192.0.2.12' );
    is( $protected_count, 0,
        'closing a spam report with a padded protected IP does not create a sysban' );

    my $r_allowed = $run_del->('192.0.2.99%0A');
    is( $r_allowed->status, 200, 'spam report closure with padded allowed IP succeeds' );
    my ($allowed_banid) = $dbh->selectrow_array(
        "SELECT banid FROM sysban WHERE what = 'talk_ip_test' AND value = ?"
            . " ORDER BY banid DESC LIMIT 1",
        undef, '192.0.2.99'
    );
    ok( $allowed_banid,
        'closing a spam report with a padded allowed IP creates the trimmed sysban' );
    $dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $allowed_banid ) if $allowed_banid;
};

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
