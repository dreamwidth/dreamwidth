#!/usr/bin/perl

use Test::More tests => 12;
BEGIN { use_ok('LJ::UserSearch') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $users = 1000;
LJ::UserSearch::reset_usermeta(8 * ($users + 1));
my $now = time();
foreach my $uid (0..$users) {
    my $jtype = $uid <= 500 ? 3 : 2;
    my $reg   = $uid % 200;
    my $buf = pack("NCCCx",
                   $now - $users + $uid,    # updatetime
                   1 + ($uid % 4),          # age
                   ($jtype << 0) +   # journaltype
                   0
                   ,
                   $reg,                    # region id
                   );
    LJ::UserSearch::add_usermeta($buf, 8);
}


# match 5 and 7:
LJ::UserSearch::init_new_search();

LJ::UserSearch::isect_begin(12);
LJ::UserSearch::isect_push("\xff\0\0\x04\0\0\0\x05");
LJ::UserSearch::isect_push("\0\0\0\x07");
LJ::UserSearch::isect_end();

LJ::UserSearch::isect("\0\0\0\x08\0\0\0\x05\0\0\0\x07");
LJ::UserSearch::isect("\0\0\0\x04\0\0\0\x05\0\0\0\x07\xff\xff\xff\x04");
my $res = LJ::UserSearch::get_results();
is_deeply($res, [7, 5], "matches 5 and 7");

#use Data::Dumper;
#print Dumper($res);


# match 5 and 8:
my $lastres;

for (1..5) {
    LJ::UserSearch::init_new_search();
      LJ::UserSearch::isect("\0\0\0\x04\0\0\0\x05\0\0\0\x08");
      LJ::UserSearch::isect("\0\0\0\x08\0\0\0\x05\0\0\0\x07");
      $lastres = LJ::UserSearch::get_results();
      if ($_ == 1) {
          #objs();
      }
  }
is_deeply($lastres, [8, 5], "matches 5 and 8");

# test age ranges:
{
    LJ::UserSearch::init_new_search();
    LJ::UserSearch::isect_age_range(2, 3);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 500, "matched 500 items");
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 500, "got results, again, still 500 items");
    LJ::UserSearch::isect_age_range(1, 2);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 250, "got results after 1-2, now 250 items");
    LJ::UserSearch::isect("\0\0\0\x08\0\0\0\x05\0\0\0\x07");
    $lastres = LJ::UserSearch::get_results();
    is_deeply($lastres, [5], "intersected down another set, just got 5");
}

# test update times
{
    LJ::UserSearch::init_new_search();
    LJ::UserSearch::isect_updatetime_gte($now - 50);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 51, "got 51 results");
    LJ::UserSearch::isect_updatetime_gte($now - 25);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 26, "got 26 results");
}

# test journaltype
{
    LJ::UserSearch::init_new_search();
    LJ::UserSearch::isect_journal_type(3);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 500, "got 500 journaltype 3 results");
}

# test region
{
    LJ::UserSearch::init_new_search();
    my $reg = "\0" x 256;
    vec($reg, 1, 8) = 1;
    LJ::UserSearch::isect_region_map($reg);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 5, "got 5 people in region 1");

    # add another region
    vec($reg, 2, 8) = 1;
    LJ::UserSearch::init_new_search();
    LJ::UserSearch::isect_region_map($reg);
    $lastres = LJ::UserSearch::get_results();
    is(scalar @$lastres, 10, "got 10 people in regions 1 or 2");

}


#objs();

# TODO: test isect_push without isect_begin
# TODO: test isect_push overflowing length in isect_begin

sub objs {
    eval "use Devel::Gladiator; use Devel::Peek; 1";
    my $all = Devel::Gladiator::walk_arena();
    my %ct;
    foreach my $it (@$all) {
        $ct{ref $it}++;
        if (ref $it eq "CODE") {
            my $name = Devel::Peek::CvGV($it);
            $ct{$name}++ if $name =~ /ANON/;
        }
    }
    $all = undef;  # required to free memory
    foreach my $n (sort { $ct{$a} <=> $ct{$b} } keys %ct) {
        next unless $ct{$n} > 1;
        printf("%7d $n\n", $ct{$n});
    }
}
