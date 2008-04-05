# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::ContentFlag;
use LJ::Test;

my $u = temp_user();
my $u2 = temp_user();
my $u3 = temp_user();
my $u4 = temp_user();

my @flags;

my $entry = $u->t_post_fake_entry();
my $flag = LJ::ContentFlag->flag(item => $entry, reporter => $u2, journal => $u, cat => LJ::ContentFlag::CHILD_PORN);
ok($flag, "flagged entry");
push @flags, $flag;

ok($flag->flagid, "got flag id");

is($flag->status, LJ::ContentFlag::NEW, "flag is new");
is($flag->catid, LJ::ContentFlag::CHILD_PORN, "flag cat");
is($flag->modtime, undef, "no modtime");

my $time = time();
$flag->set_status(LJ::ContentFlag::CLOSED);
is($flag->status, LJ::ContentFlag::CLOSED, "status change");
ok(($flag->modtime - $time) < 2, "modtime");

my $flagid = $flag->flagid;

my ($dbflag) = LJ::ContentFlag->load_by_flagid($flagid);
ok($dbflag, "got flag object loading by flagid");
is_deeply($dbflag, $flag, "loaded same flag from db");

$flag->set_status(LJ::ContentFlag::NEW);

($dbflag) = LJ::ContentFlag->load_by_flagid($flagid, lock => 1);
ok($dbflag, "load_outstanding");

($dbflag) = LJ::ContentFlag->load_by_flagid($flagid, lock => 1);
ok(! $dbflag, "didn't get locked flag");

my $flag2 = LJ::ContentFlag->flag(item => $entry, reporter => $u3, journal => $u, cat => LJ::ContentFlag::CHILD_PORN);
push @flags, LJ::ContentFlag->flag(item => $entry, reporter => $u4, journal => $u, cat => LJ::ContentFlag::CHILD_PORN);
push @flags, LJ::ContentFlag->flag(item => $entry, reporter => $u3, journal => $u, cat => LJ::ContentFlag::ILLEGAL_CONTENT);
push @flags, $flag2;

my @flags = LJ::ContentFlag->load_by_journal($u, group => 1);
is($flags[0]->count, 4, "group by");

$flag2->set_field('instime', 10);
($dbflag) = LJ::ContentFlag->load_by_flagid($flag2->flagid, from => 10);
ok(! $dbflag, "time constraint");

($dbflag) = LJ::ContentFlag->load_by_flagid($flag2->flagid, from => 9);
ok($dbflag, "time constraint");

# test rate limiting
{
    push @flags, LJ::ContentFlag->flag(item => $entry, reporter => $u3, journal => $u, cat => LJ::ContentFlag::ILLEGAL_CONTENT);
    push @flags, LJ::ContentFlag->flag(item => $entry, reporter => $u3, journal => $u, cat => LJ::ContentFlag::ILLEGAL_CONTENT);

    ok($u3->can_flag_content, 'not rate limited');
    push @flags, LJ::ContentFlag->flag(item => $entry, reporter => $u3, journal => $u, cat => LJ::ContentFlag::ILLEGAL_CONTENT);

    ok(! $u3->can_flag_content, 'rate limited');
}

END {
    $_->delete foreach @flags;
};
