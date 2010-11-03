# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user);
local $LJ::T_NO_COMMAND_PRINT = 1;

plan tests => 14;

my $u = temp_user();
my $u2 = temp_user();

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_remote($u);

# ------ RESET EMAIL -------
is($run->("reset_email " . $u2->user . " resetemail\@$LJ::DOMAIN \"resetting email\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("reset_email");

is($run->("reset_email " . $u2->user . " resetemail\@$LJ::DOMAIN \"resetting email\""),
   "success: Email address for '" . $u2->user . "' reset.");
$u2 = LJ::load_user($u2->user);

is($u2->email_raw, "resetemail\@$LJ::DOMAIN", "Email reset correctly.");
is($u2->email_status, "T", "Email status set correctly.");

my $dbh = LJ::get_db_reader();
my $rv = $dbh->do("SELECT * FROM infohistory WHERE userid=? AND what='email'", undef, $u2->id);
ok($rv < 1, "Addresses wiped from infohistory.");

$u->revoke_priv("reset_email");


# ------ RESET PASSWORD --------

is($run->("reset_password " . $u2->user . " \"resetting password\""),
   "error: You are not authorized to run this command.");
$u->grant_priv("reset_password");

my $oldpass = $u2->password;

is($run->("reset_password " . $u2->user . " \"resetting password\""),
   "success: Password reset for '" . $u2->user . "'.");
$u2 = LJ::load_user($u2->user);
ok($u2->password ne $oldpass, "Password changed successfully.");

$u->revoke_priv("reset_password");


# ------ EMAIL ALIASES ----------
my $user = $u2->user;
my $alias = $u2->site_email_alias;

is($run->("email_alias show $user"),
   "error: You are not authorized to run this command.");
$u->grant_priv("reset_email");

is($run->("email_alias show $user"),
   "error: $alias is not currently defined.");

is($run->("email_alias set $user testing\@example.com"),
   "success: Successfully set $alias => testing\@example.com");

is($run->("email_alias show $user"),
   "success: $alias aliases to testing\@example.com");

is($run->("email_alias delete $user"),
   "success: Successfully deleted $alias alias.");

is($run->("email_alias show $user"),
   "error: $alias is not currently defined.");

$u->revoke_priv("reset_email");
