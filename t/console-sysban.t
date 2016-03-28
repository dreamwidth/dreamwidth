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

use Test::More tests => 17;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::Console;
use LJ::Test qw (temp_user);
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
    my $msg = $run->( $cmd );
    my ( $text, $banid ) = split( "#", $msg );
    is( $text, "success: Successfully created ban ",
        "Successfully created sysban" );
    # must wait: sysban_check compares bandate to NOW();
    sleep 2;
    return $banid;
};

# -- SYSBAN ADD --

my $test_ip = '500.500.500.500';
my $test_domain2 = 'dw.bogus';
my $test_domain3 = 'dw.totally.bogus';
my $test_domain_bogus = 'totally.bogus';

is( $run->( "sysban_add talk_ip_test $test_ip 7 testing" ),
    "error: You are not authorized to run this command." );

$u->grant_priv( "sysban", "talk_ip_test" );

ok( ! LJ::sysban_check( "talk_ip_test", $test_ip ),
    "Not currently sysbanned" );

my $banid_talk_ip_test =
    $do_ban->( "sysban_add talk_ip_test $test_ip 7 testing" );

ok( LJ::sysban_check( "talk_ip_test", $test_ip ),
    "Successfully sysbanned test_ip" );

is($run->("sysban_add talk_ip_test not-an-ip-address 7 testing"),
   "error: Format: xxx.xxx.xxx.xxx (ip address)");

is($run->( "sysban_add ip $test_ip 7 testing" ),
   "error: You cannot create these ban types");

# test email addresses for banned domains
$u->grant_priv( "sysban", "email_domain" );

my $banid_email_domain2 =
    $do_ban->( "sysban_add email_domain $test_domain2 7 testing" );

ok( LJ::sysban_check( "email_domain", $test_domain2 ),
    "Successfully sysbanned test_domain2" );

ok( LJ::sysban_check( "email", "user\@$test_domain2" ),
    "Successfully sysbanned user\@test_domain2" );

my $banid_email_domain3 =
    $do_ban->( "sysban_add email_domain $test_domain3 7 testing" );

ok( LJ::sysban_check( "email_domain", $test_domain3 ),
    "Successfully sysbanned test_domain3" );

ok( LJ::sysban_check( "email", "user\@$test_domain3" ),
    "Successfully sysbanned user\@test_domain3" );

ok( ! LJ::sysban_check( "email_domain", $test_domain_bogus ),
    "Make sure only the three-element subdomain is banned" );

ok( ! LJ::sysban_check( "email", "user\@$test_domain_bogus" ),
    "Make sure only the three-element subdomain is banned for user" );

# cleanup
my $dbh = LJ::get_db_writer();
$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_talk_ip_test );
$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_email_domain2 );
$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_email_domain3 );

# one last check to make sure we are checking domains properly -
# all subdomains of a banned domain should be rejected as well
my $banid_domain_bogus =
    $do_ban->( "sysban_add email_domain $test_domain_bogus 7 testing" );

ok( ! LJ::sysban_check( "email_domain", $test_domain3 ),
    "No more sysban for test_domain3" );

ok( LJ::sysban_check( "email", "user\@$test_domain3" ),
    "Still sysbanned user\@test_domain3 using test_domain_bogus" );

$dbh->do( "DELETE FROM sysban WHERE banid = ?", undef, $banid_domain_bogus );
