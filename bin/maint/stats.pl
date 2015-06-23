#!/usr/bin/perl
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
our %maint;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use LJ::Stats;

# filled in by ljmaint.pl, 0=quiet, 1=normal, 2=verbose
$LJ::Stats::VERBOSE = $LJ::LJMAINT_VERBOSE >= 2 ? 1 : 0;

$maint{'genstats'} = sub
{
    my @which = @_ || qw(users countries
                         states gender clients
                         pop_interests popfaq);

    # popular faq items
    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "popfaq",
           'statname' => "pop_faq",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   my $sth = $db->prepare("SELECT faqid, COUNT(*) FROM faquses WHERE " .
                                          "faqid<>0 GROUP BY 1 ORDER BY 2 DESC LIMIT 50");
                   $sth->execute;
                   die $db->errstr if $db->err;

                   my %ret;
                   while (my ($id, $count) = $sth->fetchrow_array) {
                       $ret{$id} = $count;
                   }

                   return \%ret;
               },

        });

    # popular interests
    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "pop_interests",
           'statname' => "pop_interests",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   return {} unless LJ::is_enabled('interests-popular');

                   # see what the previous min was, then subtract 20% of max from it
                   my ($prev_min, $prev_max) = $db->selectrow_array("SELECT MIN(statval), MAX(statval) " .
                                                                    "FROM stats WHERE statcat='pop_interests'");
                   my $stat_min = int($prev_min - (0.2*$prev_max));
                   $stat_min = 1 if $stat_min < 1;

                   my $sth = $db->prepare( "SELECT k.keyword, i.intcount FROM interests AS i, sitekeywords AS k " .
                                           "WHERE k.kwid=i.intid AND i.intcount>? " .
                                           "ORDER BY i.intcount DESC, k.keyword ASC LIMIT 400" );
                   $sth->execute($stat_min);
                   die $db->errstr if $db->err;

                   my %ret;
                   while (my ($int, $count) = $sth->fetchrow_array) {
                       $ret{$int} = $count;
                   }

                   return \%ret;
               },

       });

    # clients
    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "clients",
           'statname' => "client",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   return {} unless LJ::is_enabled('clientversionlog');

                   my $usertotal = $db->selectrow_array("SELECT MAX(userid) FROM user");
                   my $blocks = LJ::Stats::num_blocks($usertotal);

                   my %ret;
                   foreach my $block (1..$blocks) {
                       my ($low, $high) = LJ::Stats::get_block_bounds($block);

                       $db = $db_getter->(); # revalidate connection
                       my $sth = $db->prepare("SELECT c.client, COUNT(*) AS 'count' FROM clients c, clientusage cu " .
                                              "WHERE c.clientid=cu.clientid AND cu.userid BETWEEN $low AND $high " .
                                              "AND cu.lastlogin > DATE_SUB(NOW(), INTERVAL 30 DAY) GROUP BY 1 ORDER BY 2");
                       $sth->execute;
                       die $db->errstr if $db->err;

                       while ($_ = $sth->fetchrow_hashref) {
                           $ret{$_->{'client'}} += $_->{'count'};
                       }

                       print LJ::Stats::block_status_line($block, $blocks);
                   }

                   return \%ret;
               },
         });


    # user table analysis
    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "users",
           'statname' => ["account", "newbyday", "age", "userinfo"],
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   my $usertotal = $db->selectrow_array("SELECT MAX(userid) FROM user");
                   my $blocks = LJ::Stats::num_blocks($usertotal);

                   my %ret; # return hash, (statname => { arg => val } since 'statname' is arrayref above

                   # iterate over user table in batches
                   foreach my $block (1..$blocks) {

                       my ($low, $high) = LJ::Stats::get_block_bounds($block);

                       # user query: gets user,caps,age,status,allow_getljnews
                       $db = $db_getter->(); # revalidate connection
                       my $sth = $db->prepare
                           ("SELECT user, caps, " .
                            "FLOOR((TO_DAYS(NOW())-TO_DAYS(bdate))/365.25) AS 'age', " .
                            "status, allow_getljnews " .
                            "FROM user WHERE userid BETWEEN $low AND $high");
                       $sth->execute;
                       die $db->errstr if $db->err;
                       while (my $rec = $sth->fetchrow_hashref) {

                           # account types
                           my $capnameshort = LJ::Capabilities::name_caps_short( $rec->{caps} );
                           $ret{'account'}->{$capnameshort}++;

                           # ages
                           $ret{'age'}->{$rec->{'age'}}++
                               if $rec->{'age'} > 4 && $rec->{'age'} < 110;

                           # users receiving news emails
                           $ret{'userinfo'}->{'allow_getljnews'}++
                               if $rec->{'status'} eq "A" && $rec->{'allow_getljnews'} eq "Y";
                       }

                       # userusage query: gets timeupdate,datereg,nowdate
                       my $sth = $db->prepare
                           ("SELECT DATE_FORMAT(timecreate, '%Y-%m-%d') AS 'datereg', " .
                            "DATE_FORMAT(NOW(), '%Y-%m-%d') AS 'nowdate', " .
                            "UNIX_TIMESTAMP(timeupdate) AS 'timeupdate' " .
                            "FROM userusage WHERE userid BETWEEN $low AND $high");
                       $sth->execute;
                       die $db->errstr if $db->err;

                       while (my $rec = $sth->fetchrow_hashref) {

                           # date registered
                           $ret{'newbyday'}->{$rec->{'datereg'}}++
                               unless $rec->{'datereg'} eq $rec->{'nowdate'};

                           # total user/activity counts
                           $ret{'userinfo'}->{'total'}++;
                           if (my $time = $rec->{'timeupdate'}) {
                               my $now = time();
                               $ret{'userinfo'}->{'updated'}++;
                               $ret{'userinfo'}->{'updated_last30'}++ if $time > $now-60*60*24*30;
                               $ret{'userinfo'}->{'updated_last7'}++ if $time > $now-60*60*24*7;
                               $ret{'userinfo'}->{'updated_last1'}++ if $time > $now-60*60*24*1;
                           }
                       }

                       print LJ::Stats::block_status_line($block, $blocks);
                   }

                   return \%ret;
               },
           });


    LJ::Stats::register_stat
        ({ 'type' => "clustered",
           'jobname' => "countries",
           'statname' => "country",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   my $cid = shift;
                   return undef unless $db && $cid;

                   my $upc = LJ::get_prop("user", "country");
                   die "Can't find country userprop.  Database populated?\n" unless $upc;

                   my $usertotal = $db->selectrow_array("SELECT MAX(userid) FROM userproplite2");
                   my $blocks = LJ::Stats::num_blocks($usertotal);

                   my %ret;
                   foreach my $block (1..$blocks) {
                       my ($low, $high) = LJ::Stats::get_block_bounds($block);

                       $db = $db_getter->(); # revalidate connection
                       my $sth = $db->prepare("SELECT u.value, COUNT(*) AS 'count' FROM userproplite2 u " .
                                              "LEFT JOIN clustertrack2 c ON u.userid=c.userid " .
                                              "WHERE u.upropid=? AND u.value<>'' AND u.userid=c.userid " .
                                              "AND u.userid BETWEEN $low AND $high " .
                                              "AND (c.clusterid IS NULL OR c.clusterid=?)" .
                                              "GROUP BY 1 ORDER BY 2");
                       $sth->execute($upc->{'id'}, $cid);
                       die "clusterid: $cid, " . $db->errstr if $db->err;

                       while ($_ = $sth->fetchrow_hashref) {
                           $ret{$_->{'value'}} += $_->{'count'};
                       }

                       print LJ::Stats::block_status_line($block, $blocks);
                   }

                   return \%ret;
               },
           });


    LJ::Stats::register_stat
        ({ 'type' => "clustered",
           'jobname' => "states",
           'statname' => "stateus",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   my $cid = shift;
                   return undef unless $db && $cid;

                   my $upc = LJ::get_prop("user", "country");
                   die "Can't find country userprop.  Database populated?\n" unless $upc;

                   my $ups = LJ::get_prop("user", "state");
                   die "Can't find state userprop.  Database populated?\n" unless $ups;

                   my $usertotal = $db->selectrow_array("SELECT MAX(userid) FROM userproplite2");
                   my $blocks = LJ::Stats::num_blocks($usertotal);

                   my %ret;
                   foreach my $block (1..$blocks) {
                       my ($low, $high) = LJ::Stats::get_block_bounds($block);

                       $db = $db_getter->(); # revalidate connection
                       my $sth = $db->prepare("SELECT ua.value, COUNT(*) AS 'count' " .
                                              "FROM userproplite2 ua, userproplite2 ub " .
                                              "WHERE ua.userid=ub.userid AND ua.upropid=? AND " .
                                              "ub.upropid=? and ub.value='US' AND ub.value<>'' " .
                                              "AND ua.userid BETWEEN $low AND $high " .
                                              "GROUP BY 1 ORDER BY 2");
                       $sth->execute($ups->{'id'}, $upc->{'id'});
                       die $db->errstr if $db->err;

                       while ($_ = $sth->fetchrow_hashref) {
                           $ret{$_->{'value'}} += $_->{'count'};
                       }

                       print LJ::Stats::block_status_line($block, $blocks);
                   }

                   return \%ret;
               },

           });


    LJ::Stats::register_stat
        ({ 'type' => "clustered",
           'jobname' => "gender",
           'statname' => "gender",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   my $cid = shift;
                   return undef unless $db && $cid;

                   my $upg = LJ::get_prop("user", "gender");
                   die "Can't find gender userprop.  Database populated?\n" unless $upg;

                   my $usertotal = $db->selectrow_array("SELECT MAX(userid) FROM userproplite2");
                   my $blocks = LJ::Stats::num_blocks($usertotal);

                   my %ret;
                   foreach my $block (1..$blocks) {
                       my ($low, $high) = LJ::Stats::get_block_bounds($block);

                       $db = $db_getter->(); # revalidate connection
                       my $sth = $db->prepare("SELECT value, COUNT(*) AS 'count' FROM userproplite2 up " .
                                              "LEFT JOIN clustertrack2 c ON up.userid=c.userid " .
                                              "WHERE up.upropid=? AND up.userid BETWEEN $low AND $high " .
                                              "AND (c.clusterid IS NULL OR c.clusterid=?) GROUP BY 1");
                       $sth->execute($upg->{'id'}, $cid);
                       die "clusterid: $cid, " . $db->errstr if $db->err;

                       while ($_ = $sth->fetchrow_hashref) {
                           $ret{$_->{'value'}} += $_->{'count'};
                       }

                       print LJ::Stats::block_status_line($block, $blocks);
                   }

                   return \%ret;
               },

         });


    # run stats
    LJ::Stats::run_stats(@which);

    #### dump to text file
    print "-I- Dumping to a text file.\n";

    {
        my $dbh = LJ::Stats::get_db("dbh");
        my $sth = $dbh->prepare
            ("SELECT statcat, statkey, statval FROM stats ORDER BY 1, 2");
        $sth->execute;
        die $dbh->errstr if $dbh->err;

        open (OUT, ">$LJ::HTDOCS/stats/stats.txt");
        while (my @row = $sth->fetchrow_array) {
            next if grep { $row[0] eq $_ } @LJ::PRIVATE_STATS;
            print OUT join("\t", @row), "\n";
        }
        close OUT;
    }

    print "-I- Done.\n";

};

$maint{'genstats_size'} = sub {

    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "size-accounts",
           'statname' => "size",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   # not that this isn't a total of current accounts (some rows may have
                   # been deleted), but rather a total of accounts ever created
                   my $size = $db->selectrow_array("SELECT MAX(userid) FROM user");
                   return { 'accounts' => $size };
               },
         });

    LJ::Stats::register_stat
        ({ 'type' => "clustered",
           'jobname' => "size-accounts_active",
           'statname' => "size",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   my @intervals = qw(1 7 30);

                   my $max_age = 86400 * $intervals[-1];
                   my $sth = $db->prepare
                       ("SELECT FLOOR((UNIX_TIMESTAMP()-timeactive)/86400), COUNT(*) " .
                        "FROM clustertrack2 " .
                        "WHERE timeactive > UNIX_TIMESTAMP()-$max_age GROUP BY 1");
                   $sth->execute;

                   my %ret = ();
                   while (my ($days, $active) = $sth->fetchrow_array) {

                       # which day interval does this fall in?
                       # -- in last day, in last 7, in last 30?
                       foreach my $int (@intervals) {
                           $ret{$int} += $active if $days < $int;
                       }
                   }

                   return { map { ("accounts_active_$_" => $ret{$_}+0) } @intervals };
               },
         });

    print "-I- Generating account size stats.\n";
    LJ::Stats::run_stats("size-accounts", "size-accounts_active");
    print "-I- Done.\n";
};


$maint{'genstats_weekly'} = sub
{
    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "supportrank_prev",
           'statname' => "supportrank_prev",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   my $rows = $db->selectall_arrayref( "SELECT statkey, statval FROM stats WHERE statcat = 'supportrank'" );
                   return {} unless $rows;

                   return { ( map { $_->[0] => $_->[1] } @$rows ) };
               }
        });

    LJ::Stats::register_stat
        ({ 'type' => "global",
           'jobname' => "supportrank",
           'statname' => "supportrank",
           'handler' =>
               sub {
                   my $db_getter = shift;
                   return undef unless ref $db_getter eq 'CODE';
                   my $db = $db_getter->();
                   return undef unless $db;

                   my %supportrank;
                   my $rank = 0;
                   my $lastpoints = 0;
                   my $buildup = 0;

                   my $sth = $db->prepare
                       ("SELECT userid, SUM(points) AS 'points' " .
                        "FROM supportpoints " .
                        "GROUP BY 1 ORDER BY 2 DESC");
                   $sth->execute;
                   die $db->errstr if $db->err;

                   while ($_ = $sth->fetchrow_hashref) {
                       if ($lastpoints != $_->{'points'}) {
                           $lastpoints = $_->{'points'};
                           $rank += (1 + $buildup);
                           $buildup = 0;
                       } else {
                           $buildup++;
                       }
                       $supportrank{$_->{'userid'}} = $rank;
                   }

                   return \%supportrank;
               }
        });

    print "-I- Generating weekly stats.\n";
    LJ::Stats::run_stats('supportrank_prev', 'supportrank');
    print "-I- Done.\n";
};


1;
