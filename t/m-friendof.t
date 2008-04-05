# -*-perl-*-

use strict;
use Test::More tests => 144;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use FindBin qw($Bin);
use LJ::Test qw(memcache_stress temp_user temp_comm);
use LJ::M::FriendsOf;

local $LJ::_T_FAST_TEMP_USER = 1;  # don't do post-create hook

our @STATUSVIS;
our $PREFIX;
our $MUTUALS_SEPARATE;
our $USER_COUNT;
our $COMM_COUNT;
our $LOAD_LIMIT;
our $SLOPPY;

{
    local @STATUSVIS = qw(V);
    local $PREFIX = "Only Visibles";
    local $MUTUALS_SEPARATE = 0;
    local $USER_COUNT = 25;
    local $COMM_COUNT = 10;
    local $LOAD_LIMIT = 300;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Visible & Deleted";
    local $MUTUALS_SEPARATE = 0;
    local $USER_COUNT = 40;
    local $COMM_COUNT = 5;
    local $LOAD_LIMIT = 400;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Mutuals separate";
    local $MUTUALS_SEPARATE = 1;
    local $USER_COUNT = 50;
    local $COMM_COUNT = 7;
    local $LOAD_LIMIT = 500;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Cropped";
    local $MUTUALS_SEPARATE = 1;
    local $USER_COUNT = 50;
    local $COMM_COUNT = 13;
    local $LOAD_LIMIT = 5;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Cropped & Sloppy";
    local $MUTUALS_SEPARATE = 0;
    local $USER_COUNT = 50;
    local $COMM_COUNT = 11;
    local $LOAD_LIMIT = 5;
    local $SLOPPY = 1;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Cropped & Sloppy, mutuals separate";
    local $MUTUALS_SEPARATE = 1;
    local $USER_COUNT = 50;
    local $COMM_COUNT = 0;
    local $LOAD_LIMIT = 5;
    local $SLOPPY = 1;
    memcache_stress(\&run_all);
}

sub run_all {
    LJ::start_request();

    my $u = temp_user();

    my @expected_friends;
    my @expected_friendofs;
    my @expected_mutual;
    my @expected_memberofs;
    my $expected_readers = 0;

    foreach (1..$USER_COUNT) {
        my $f = temp_user();
        my $statusvis = @STATUSVIS[rand @STATUSVIS];
        LJ::update_user( $f, { statusvis => $statusvis } );

        my $fid = $f->id;
        my $rand = rand();
        if ($rand < .33) {
            LJ::add_friend($u, $f) or die;
            LJ::add_friend($f, $u) or die;
            push @expected_friends, $fid;
            $expected_readers++;
            if ($statusvis eq 'V') {
                push @expected_mutual, $fid;
                push @expected_friendofs, $fid unless $MUTUALS_SEPARATE;
            }
        } elsif ($rand < .67) {
            LJ::add_friend($u, $f) or die;
            push @expected_friends, $fid;
        } else {
            LJ::add_friend($f, $u) or die;
            $expected_readers++;
            push @expected_friendofs, $fid if $statusvis eq 'V';
        }
    }

    foreach (1..$COMM_COUNT) {
        my $c = temp_comm();

        my $cid = $c->id;

        my $rand = rand();
        if ($rand < .33) {
            LJ::add_friend($u, $c) or die;
            LJ::add_friend($c, $u) or die;
            push @expected_friends, $cid;
            push @expected_memberofs, $cid;
            $expected_readers++;
        } elsif ($rand < .67) {
            LJ::add_friend($u, $c) or die;
            push @expected_friends, $cid;
        } else {
            LJ::add_friend($c, $u) or die;
            $expected_readers++;
            push @expected_memberofs, $cid;
        }
    }

    my @friends = $u->friends;

    is_deeply([sort(map {$_->id} @friends)], [sort @expected_friends], "$PREFIX: Friends");

    my %friends = map { $_->id, $_ } @friends;
    my $fo_m = LJ::M::FriendsOf->new($u, sloppy => $SLOPPY, load_cap => $LOAD_LIMIT, mutuals_separate => $MUTUALS_SEPARATE, friends => { %friends });

    {
        my @friendofs = map { $_->id } $fo_m->friend_ofs;
        is_in([sort @friendofs], [sort @expected_friendofs], "$PREFIX: Friendofs");
    }

    SKIP: {
        my $friendofs = $fo_m->friend_ofs;
        if ($SLOPPY && $LOAD_LIMIT < $USER_COUNT) {
            skip "Friendofs count of $friendofs will be wrong compared to " . @expected_friendofs, 1;
        }
        is($friendofs, @expected_friendofs, "$PREFIX: Friendofs count");
    }

    {
        my @member_of = map { $_->id } $fo_m->member_of;
        is_in([sort @member_of], [sort @expected_memberofs], "$PREFIX: Memberofs");
    }

    SKIP: {
        my $member_of = $fo_m->member_of;
        if ($SLOPPY && $LOAD_LIMIT < $USER_COUNT) {
            skip "Member ofs count of $member_of will be wrong compared to " . @expected_memberofs, 1;
        }
        is($member_of, @expected_memberofs, "$PREFIX: Memberofs count");
    }

    # Treating this user as a community now, even though it technically isn't.
    SKIP: {
        my $reader_count = $fo_m->reader_count;
        if ($SLOPPY && $LOAD_LIMIT < $USER_COUNT) {
            skip "Reader count of $reader_count will be wrong compared to " . @expected_friendofs, 1;
        }
        is($reader_count, $expected_readers, "$PREFIX: Reader count");
    }

    {
        my @mutual_friends = map { $_->id} $fo_m->mutual_friends;
        is_in([sort @mutual_friends], [sort @expected_mutual], "$PREFIX: Mutual friends");
    }

    {
        my $mutual_friends = $fo_m->mutual_friends;
        is($mutual_friends, @expected_mutual, "$PREFIX: Mutual friends count");
    }
}

sub is_in {
    my ($l, $r, $description) = @_;

    $description .= " (sloppy)" if $SLOPPY;

    my $cropped = $LOAD_LIMIT < $USER_COUNT;
    $description .= " (cropped)" if $LOAD_LIMIT < $USER_COUNT;


    return is_deeply($l, $r, $description) unless $SLOPPY || $cropped;

    my $left_count = @$l;
    my $right_count = @$r;

    return fail("$description: left side longer than right") if $left_count > $right_count;

    my %r = map { $_, 1 } @$r;
    my @failed;
    foreach my $check (@$l) {
        next if $r{$check};
        push @failed, $check;
    }

    return fail("$description: " . scalar @failed . " items were in left and not in right.") if @failed;
    return pass("$description matched $left_count of $right_count possible.");
}

# vim: filetype=perl
