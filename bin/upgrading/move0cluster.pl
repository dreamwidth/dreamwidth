#!/usr/bin/perl
#
# Moves a user between clusters.
#

use strict;
use Getopt::Long;

my $opt_del = 0;
my $opt_destdel = 0;
my $opt_useslow = 0;
my $opt_slowalloc = 0;
my $opt_verbose = 1;
my $opt_movemaster = 0;
my $opt_prelocked = 0;
my $opt_expungedel = 0;
my $opt_ignorebit = 0;
exit 1 unless GetOptions('delete' => \$opt_del,
                         'destdelete' => \$opt_destdel,
                         'useslow' => \$opt_useslow, # use slow db role for read
                         'slowalloc' => \$opt_slowalloc, # see note below
			 'verbose=i' => \$opt_verbose,
			 'movemaster|mm' => \$opt_movemaster,
                         'prelocked' => \$opt_prelocked,
			 'expungedel' => \$opt_expungedel,
			 'ignorebit' => \$opt_ignorebit,
                         );
my $optv = $opt_verbose;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljcmdbuffer.pl";

my $dbh = LJ::get_dbh({raw=>1}, "master");
die "No master db available.\n" unless $dbh;
$dbh->do("SET wait_timeout=28800");

my $dbr = $dbh;
if ($opt_useslow) {
    $dbr = LJ::get_dbh({raw=>1}, "slow");
    unless ($dbr) { die "Can't get slow db from which to read.\n"; }
}

my $user = LJ::canonical_username(shift @ARGV);
my $dclust = shift @ARGV;

# tables which are dumbly copied by sucking all into memory first.
# use smarter mover code for anything that shouldn't all go into memory.
# also, to use this you have to define the primary keys below
my @manual_move = qw(loginstall ratelog sessions userproplite2
                     sessions_data userbio userpicblob2 userpropblob
                     s1usercache modlog modblob counter
                     s1style s1overrides links userblob clustertrack2);
sub usage {
    die "Usage:\n  movecluster.pl <user> <destination cluster #>\n";
}

usage() unless defined $user;
usage() unless defined $dclust;

die "Failed to get move lock.\n"
    unless ($dbh->selectrow_array("SELECT GET_LOCK('moveucluster-$user', 10)"));

my $u = $dbh->selectrow_hashref("SELECT * FROM user WHERE user=?", undef, $user);
die "Non-existent user $user.\n" unless $u;

die "Can't move back to legacy cluster 0\n" unless $dclust;

my $dbch = LJ::get_cluster_master({raw=>1}, $dclust);

die "Undefined or down cluster \#$dclust\n" unless $dbch;
$dbch->do("SET wait_timeout=28800");

my $separate_cluster = LJ::use_diff_db("master", "cluster$dclust");

$dbh->{'RaiseError'} = 1;
$dbch->{'RaiseError'} = 1;

my $sclust = $u->{'clusterid'};

if ($sclust == $dclust) {
    die "User '$user' is already on cluster $dclust\n";
}

if ($sclust) {
    verify_movable_tables();
}

# original cluster db handle.
my $dbo;
if ($sclust) {
    $dbo = $opt_movemaster ?
        LJ::get_dbh({raw=>1}, "cluster$u->{clusterid}movemaster") :
	LJ::get_cluster_master({raw=>1}, $u);
    die "Can't get source cluster handle.\n" unless $dbo;
    $dbo->{'RaiseError'} = 1;
    $dbo->do("SET wait_timeout=28800");
}

my $userid = $u->{'userid'};

# find readonly cap class, complain if not found
my $readonly_bit = undef;
foreach (keys %LJ::CAP) {
    if ($LJ::CAP{$_}->{'_name'} eq "_moveinprogress" &&
        $LJ::CAP{$_}->{'readonly'} == 1) {
        $readonly_bit = $_;
        last;
    }
}
unless (defined $readonly_bit) {
    die "Won't move user without %LJ::CAP capability class named '_moveinprogress' with readonly => 1\n";
}

# make sure a move isn't already in progress
if ($opt_prelocked) {
    unless (($u->{'caps'}+0) & (1 << $readonly_bit)) {
        die "User '$user' should have been prelocked.\n";
    }
} else {
    if (($u->{'caps'}+0) & (1 << $readonly_bit)) {
        die "User '$user' is already in the process of being moved? (cap bit $readonly_bit set)\n"
            unless $opt_ignorebit;
    }
}

if ($opt_expungedel && $u->{'statusvis'} eq "D" &&
    LJ::mysqldate_to_time($u->{'statusvisdate'}) < time() - 86400*31) {

    print "Expunging user '$u->{'user'}'\n";
    $dbh->do("INSERT INTO clustermove (userid, sclust, dclust, timestart, timedone) ".
	     "VALUES (?,?,?,UNIX_TIMESTAMP(),UNIX_TIMESTAMP())", undef, 
	     $userid, $sclust, 0);
    LJ::update_user($userid, { clusterid => 0,
                               statusvis => 'X',
			       raw => "caps=caps&~(1<<$readonly_bit), statusvisdate=NOW()" });
    exit 0;
}

print "Moving '$u->{'user'}' from cluster $sclust to $dclust\n" if $optv >= 1;

# mark that we're starting the move
$dbh->do("INSERT INTO clustermove (userid, sclust, dclust, timestart) ".
         "VALUES (?,?,?,UNIX_TIMESTAMP())", undef, $userid, $sclust, $dclust);
my $cmid = $dbh->{'mysql_insertid'};

# set readonly cap bit on user
LJ::update_user($userid, { raw => "caps=caps|(1<<$readonly_bit)" })
    unless $opt_prelocked;
$dbh->do("SELECT RELEASE_LOCK('moveucluster-$user')");

unless ($opt_prelocked) {
# wait a bit for writes to stop if journal is somewhat active (last week update)
    my $secidle = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()-UNIX_TIMESTAMP(timeupdate) ".
                                        "FROM userusage WHERE userid=$userid");
    if ($secidle) {
        sleep(2) unless $secidle > 86400*7;
        sleep(1) unless $secidle > 86400;
    }
}

# make sure slow is caught up:
if ($opt_useslow)
{
    my $ms = $dbh->selectrow_hashref("SHOW MASTER STATUS");
    my $loop = 1;
    while ($loop) {
        my $ss = $dbr->selectrow_hashref("SHOW SLAVE STATUS");
        $loop = 0;
        unless ($ss->{'Log_File'} gt $ms->{'File'} ||
                ($ss->{'Log_File'} eq $ms->{'File'} && $ss->{'Pos'} >= $ms->{'Position'}))
        {
            $loop = 1;
            print "Waiting for slave ($ss->{'Pos'} < $ms->{'Position'})\n";
            sleep 1;
        }
    }
}

my $last = time();
my $stmsg = sub {
    my $msg = shift;
    my $now = time();
    return if ($now < $last + 1);
    $last = $now;
    print $msg;
};

my %bufcols = ();  # db|table -> scalar "(foo, anothercol, lastcol)" or undef or ""
my %bufrows = ();  # db|table -> [ []+ ]
my %bufdbmap = (); # scalar(DBI hashref) -> DBI hashref

my $flush_buffer = sub {
    my $dbandtable = shift;
    my ($db, $table) = split(/\|/, $dbandtable);
    $db = $bufdbmap{$db};
    return unless exists $bufcols{$dbandtable};
    my $sql = "REPLACE INTO $table $bufcols{$dbandtable} VALUES ";
    $sql .= join(", ",
                 map { my $r = $_;
                       "(" . join(", ",
                                  map { $db->quote($_) } @$r) . ")" }
                 @{$bufrows{$dbandtable}});
    $db->do($sql);
    delete $bufrows{$dbandtable};
    delete $bufcols{$dbandtable};
};

my $flush_all = sub {
    foreach (keys %bufcols) {
        $flush_buffer->($_);
    }
};

my $replace_into = sub {
    my $db = ref $_[0] ? shift : $dbch;  # optional first arg
    my ($table, $cols, $max, @vals) = @_;
    my $dbandtable = scalar($db) . "|$table";
    $bufdbmap{$db} = $db;
    if (exists $bufcols{$dbandtable} && $bufcols{$dbandtable} ne $cols) {
        $flush_buffer->($dbandtable);
    }
    $bufcols{$dbandtable} = $cols;
    push @{$bufrows{$dbandtable}}, [ @vals ];

    if (scalar @{$bufrows{$dbandtable}} > $max) {
        $flush_buffer->($dbandtable);
    }
};

# assume never tried to move this user before.  however, if reported crap
# in the oldids table, we'll revert to slow alloc_id functionality,
# where we do a round-trip to $dbh for everything and see if every id
# has been remapped already.  otherwise we do it in perl and batch
# updates to the oldids table, which is the common/fast case.
my $first_move = ! $opt_slowalloc;

my %alloc_data;
my %alloc_arealast;
my $alloc_id = sub {
    my ($area, $orig) = @_;

    # fast version
    if ($first_move) {
        my $id = $alloc_data{$area}->{$orig} = ++$alloc_arealast{$area};
        $replace_into->($dbh, "oldids", "(area, oldid, userid, newid)", 250,
                        $area, $orig, $userid, $id);
        return $id;
    }

    # slow version
    $dbh->{'RaiseError'} = 0;
    $dbh->do("INSERT INTO oldids (area, oldid, userid, newid) ".
             "VALUES ('$area', $orig, $userid, NULL)");
    my $id;
    if ($dbh->err) {
        $id = $dbh->selectrow_array("SELECT newid FROM oldids WHERE area='$area' AND oldid=$orig");
    } else {
        $id = $dbh->{'mysql_insertid'};
    }
    $dbh->{'RaiseError'} = 1;
    $alloc_data{$area}->{$orig} = $id;
    return $id;
};

my $bufread;

if ($sclust == 0)
{
    # do bio stuff
    {
        my $bio = $dbr->selectrow_array("SELECT bio FROM userbio WHERE userid=$userid");
        my $bytes = length($bio);
        $dbch->do("REPLACE INTO dudata (userid, area, areaid, bytes) VALUES ($userid, 'B', 0, $bytes)");
        if ($separate_cluster) {
            $bio = $dbh->quote($bio);
            $dbch->do("REPLACE INTO userbio (userid, bio) VALUES ($userid, $bio)");
        }
    }

    my @itemids = reverse @{$dbr->selectcol_arrayref("SELECT itemid FROM log ".
                                                     "WHERE ownerid=$u->{'userid'} ".
                                                     "ORDER BY ownerid, rlogtime")};

    $bufread = make_buffer_reader("itemid", \@itemids);

    my $todo = @itemids;
    my $done = 0;
    my $stime = time();
    print "Total: $todo\n";

    # moving time, journal item at a time, and everything recursively under it
    foreach my $itemid (@itemids) {
        movefrom0_logitem($itemid);
        $done++;
        my $percent = $done/$todo;
        my $elapsed = time() - $stime;
        my $totaltime = $elapsed * (1 / $percent);
        my $timeremain = int($totaltime - $elapsed);
        $stmsg->(sprintf "$user: copy $done/$todo (%.2f%%) +${elapsed}s -${timeremain}s\n", 100*$percent);
    }

    $flush_all->();

    # update their memories.  in particular, any memories of their own
    # posts need to to be updated from the (0, globalid) to
    # (journalid, jitemid) format, to make the memory filter feature
    # work.  (it checks the first 4 bytes only, not joining the
    # globalid on the clustered log table)
    print "Fixing memories.\n";
    my @fix = @{$dbh->selectall_arrayref("SELECT memid, jitemid FROM memorable WHERE ".
                                         "userid=$u->{'userid'} AND journalid=0")};
    foreach my $f (@fix) {
        my ($memid, $newid) = ($f->[0], $alloc_data{'L'}->{$f->[1]});
        next unless $newid;
        my ($newid2, $anum) = $dbch->selectrow_array("SELECT jitemid, anum FROM log2 ".
                                                     "WHERE journalid=$u->{'userid'} AND ".
                                                     "jitemid=$newid");
        if ($newid2 == $newid) {
            my $ditemid = $newid * 256 + $anum;
            print "UPDATE $memid TO $ditemid\n";
            $dbh->do("UPDATE memorable SET journalid=$u->{'userid'}, jitemid=$ditemid ".
                     "WHERE memid=$memid");
        }
    }

    # fix polls
    print "Fixing polls.\n";
    @fix = @{$dbh->selectall_arrayref("SELECT pollid, itemid FROM poll ".
                                      "WHERE journalid=$u->{'userid'}")};
    foreach my $f (@fix) {
        my ($pollid, $newid) = ($f->[0], $alloc_data{'L'}->{$f->[1]});
        next unless $newid;
        my ($newid2, $anum) = $dbch->selectrow_array("SELECT jitemid, anum FROM log2 ".
                                                     "WHERE journalid=$u->{'userid'} AND ".
                                                     "jitemid=$newid");
        if ($newid2 == $newid) {
            my $ditemid = $newid * 256 + $anum;
            print "UPDATE $pollid TO $ditemid\n";
            $dbh->do("UPDATE poll SET itemid=$ditemid WHERE pollid=$pollid");
        }
    }

    # move userpics
    print "Copying over userpics.\n";
    my @pics = @{$dbr->selectcol_arrayref("SELECT picid FROM userpic WHERE ".
                                          "userid=$u->{'userid'}")};
    foreach my $picid (@pics) {
        print "  picid\#$picid...\n";
        my $imagedata = $dbr->selectrow_array("SELECT imagedata FROM userpicblob ".
                                              "WHERE picid=$picid");
        $imagedata = $dbh->quote($imagedata);
        $dbch->do("REPLACE INTO userpicblob2 (userid, picid, imagedata) VALUES ".
                  "($u->{'userid'}, $picid, $imagedata)");
    }

    $dbh->do("UPDATE userusage SET lastitemid=0 WHERE userid=$userid");

    my $dversion = 2;

    # if everything's good (nothing's died yet), then delete all from source
    if ($opt_del)
    {
        # before we start deleting, record they've moved servers.
        LJ::update_user($userid, { dversion => $dversion, clusterid => $dclust });

        $done = 0;
        $stime = time();
        foreach my $itemid (@itemids) {
            deletefrom0_logitem($itemid);
            $done++;
            my $percent = $done/$todo;
            my $elapsed = time() - $stime;
            my $totaltime = $elapsed * (1 / $percent);
            my $timeremain = int($totaltime - $elapsed);
            $stmsg->(sprintf "$user: delete $done/$todo (%.2f%%) +${elapsed}s -${timeremain}s\n", 100*$percent);
        }

        # delete bio from source, if necessary
        if ($separate_cluster) {
            $dbh->do("DELETE FROM userbio WHERE userid=$userid");
        }

        # delete source userpics
        print "Deleting cluster0 userpics...\n";
        foreach my $picid (@pics) {
            print "  picid\#$picid...\n";
            $dbh->do("DELETE FROM userpicblob WHERE picid=$picid");
        }

        # unset read-only bit (marks the move is complete, also, and not aborted mid-delete)
        LJ::update_user($userid, { raw => "caps=caps&~(1<<$readonly_bit)" });
        $dbh->do("UPDATE clustermove SET sdeleted='1', timedone=UNIX_TIMESTAMP() ".
                 "WHERE cmid=?", undef, $cmid);
                 
    }
    else
    {
        # unset readonly and move to new cluster in one update
        LJ::update_user($userid, { dversion => $dversion, clusterid => $dclust,
                                   raw => "caps=caps&~(1<<$readonly_bit)" });
        $dbh->do("UPDATE clustermove SET sdeleted='0', timedone=UNIX_TIMESTAMP() ".
                 "WHERE cmid=?", undef, $cmid);
    }
    exit 0;
} 
elsif ($sclust > 0) 
{
    print "Moving away from cluster $sclust\n" if $optv;

    while (my $cmd = $dbo->selectrow_array("SELECT cmd FROM cmdbuffer WHERE journalid=$userid")) {
	my $dbcm = LJ::get_cluster_master($sclust);
        print "Flushing cmdbuffer for cmd: $cmd\n" if $optv > 1;
        LJ::Cmdbuffer::flush($dbh, $dbcm, $cmd, $userid);
    }

    my $pri_key = {
        # flush this first:
        'cmdbuffer' => 'journalid',

        # this is populated as we do log/talk
        'dudata' => 'userid',

        # manual
        'loginstall' => 'userid',
        'ratelog' => 'userid',
        'sessions' => 'userid',
        'sessions_data' => 'userid',
        'userbio' => 'userid',
        'userpicblob2' => 'userid',
        'userproplite2' => 'userid',
        's1usercache' => 'userid',
        'modlog' => 'journalid',
        'modblob' => 'journalid',
        'counter' => 'journalid',
        'userblob' => 'journalid',
        'userpropblob' => 'userid',
        'clustertrack2' => 'userid',

        # log
        'log2' => 'journalid',
        'logsec2' => 'journalid',
        'logprop2' => 'journalid',
        'logtext2' => 'journalid',

        # talk
        'talk2' => 'journalid',
        'talkprop2' => 'journalid',
        'talktext2' => 'journalid',

        # no primary key... move up by posttime
        'talkleft' => 'userid',

        # s1 styles
        's1style' => 'userid',
        's1overrides' => 'userid',

        # link lists
        'links' => 'journalid',
    };

    # ask the local mods if they have any tables to move
    my @local_tables;
    my $local_tables = LJ::run_hook("moveucluster_local_tables");
    if ($local_tables) {
        while (my ($tab, $key) = each %$local_tables) {
            push @local_tables, $tab;
            $pri_key->{$tab} = $key;
        }
    }

    my @existing_data;
    print "Checking for existing data on target cluster...\n" if $optv > 1;
    foreach my $table (sort keys %$pri_key) {
        my $pri = $pri_key->{$table};
        my $is_there = $dbch->selectrow_array("SELECT $pri FROM $table WHERE $pri=$userid LIMIT 1");
        next unless $is_there;
        if ($opt_destdel) {
            while ($dbch->do("DELETE FROM $table WHERE $pri=$userid LIMIT 500") > 0) {
                print "  deleted from $table\n" if $optv;
            }
        } else {
            push @existing_data, $table;
        }
    }
    if (@existing_data) {
        die "  Existing data in tables: @existing_data\n";
    }

    my %pendreplace;  # "logprop2:(col,col)" => { 'values' => [ [a, b, c], [d, e, f] ],
                      #                           'bytes' => 3043, 'recs' => 35 }
    my $flush = sub {
        my $dest = shift;
        return 1 unless $pendreplace{$dest};
        my ($table, $cols) = split(/:/, $dest);
        my $vals;
        foreach my $v (@{$pendreplace{$dest}->{'values'}}) {
            $vals .= "," if $vals;
            $vals .= "(" . join(',', map { $dbch->quote($_) } @$v) . ")";
        }
        print "  flushing write to $table\n" if $optv > 1;
        $dbch->do("REPLACE INTO $table $cols VALUES $vals");
	die $dbh->errstr if $dbch->err;
        delete $pendreplace{$dest};
        return 1;
    };

    my $write = sub {
        my $dest = shift;
        my @values = @_;
        my $new_bytes = 0; foreach (@values) { $new_bytes += length($_); }
        push @{$pendreplace{$dest}->{'values'}}, \@values;
        $pendreplace{$dest}->{'bytes'} += $new_bytes;
        $pendreplace{$dest}->{'recs'}++;
        if ($pendreplace{$dest}->{'bytes'} > 1024*500 ||
            $pendreplace{$dest}->{'recs'} > 500) { $flush->($dest); }
    };

    my @styleids = ();

    # manual moving (dumb copies)
    foreach my $table (@manual_move, @local_tables) {
	next if ($table eq "modlog" || $table eq "modblob") && $u->{journaltype} eq "P";
        print "  moving $table ...\n" if $optv > 1;
        my @cols;
        my $sth = $dbo->prepare("DESCRIBE $table");
        $sth->execute;
        my $styleidcolnum = -1;
        my $colnum = 0;
        while ($_ = $sth->fetchrow_hashref) {
            push @cols, $_->{'Field'};
            $styleidcolnum = $colnum if $_->{'Field'} eq 'styleid';
            $colnum++;
        }
        my $cols = join(',', @cols);
        my $dest = "$table:($cols)";
        my $pri = $pri_key->{$table};
        $sth = $dbo->prepare("SELECT $cols FROM $table WHERE $pri=$userid");
        $sth->execute;
        while (my @vals = $sth->fetchrow_array) {
            $write->($dest, @vals);
            if ($styleidcolnum > -1 && $table eq 's1style') {
                push @styleids, $vals[$styleidcolnum];
            }
        }
    }

    # size of bio
    my $bio_size = $dbch->selectrow_array("SELECT LENGTH(bio) FROM userbio WHERE userid=$userid");
    $write->("dudata:(userid,area,areaid,bytes)", $userid, 'B', 0, $bio_size) if $bio_size;

    # journal items
    {
        my $maxjitem = $dbo->selectrow_array("SELECT MAX(jitemid) FROM log2 WHERE journalid=$userid");
        my $load_amt = 1000;
        my ($lo, $hi) = (1, $load_amt);
        my $sth;
        my $cols = "security,allowmask,journalid,jitemid,posterid,eventtime,logtime,compressed,anum,replycount,year,month,day,rlogtime,revttime"; # order matters.  see indexes below
        while ($lo <= $maxjitem) {
            print "  log ($lo - $hi, of $maxjitem)\n" if $optv > 1;

            # log2/logsec2
            $sth = $dbo->prepare("SELECT $cols FROM log2 ".
                                 "WHERE journalid=$userid AND jitemid BETWEEN $lo AND $hi");
            $sth->execute;
            while (my @vals = $sth->fetchrow_array) {
                $write->("log2:($cols)", @vals);

                if ($vals[0] eq "usemask") {
                    $write->("logsec2:(journalid,jitemid,allowmask)",
                             $userid, $vals[3], $vals[1]);
                }
            }

            # logprop2
            $sth = $dbo->prepare("SELECT journalid,jitemid,propid,value ".
                                 "FROM logprop2 WHERE journalid=$userid AND jitemid BETWEEN $lo AND $hi");
            $sth->execute;
            while (my @vals = $sth->fetchrow_array) {
                $write->("logprop2:(journalid,jitemid,propid,value)", @vals);
            }

            # logtext2
            $sth = $dbo->prepare("SELECT journalid,jitemid,subject,event ".
                                 "FROM logtext2 WHERE journalid=$userid AND jitemid BETWEEN $lo AND $hi");
            $sth->execute;
            while (my @vals = $sth->fetchrow_array) {
                my $size = length($vals[2]) + length($vals[3]);
                LJ::text_compress(\$vals[3]);
                $write->("logtext2:(journalid,jitemid,subject,event)", @vals);
                $write->("dudata:(userid,area,areaid,bytes)", $userid, 'L', $vals[1], $size);
            }

            $hi += $load_amt; $lo += $load_amt;
        }
    }

    # comments
    {
        my $maxtalkid = $dbo->selectrow_array("SELECT MAX(jtalkid) FROM talk2 WHERE journalid=$userid");
        my $load_amt = 1000;
        my ($lo, $hi) = (1, $load_amt);
        my $sth;
        
        my %cols = ('talk2' => 'journalid,jtalkid,nodetype,nodeid,parenttalkid,posterid,datepost,state',
                    'talkprop2' => 'journalid,jtalkid,tpropid,value',
                    'talktext2' => 'journalid,jtalkid,subject,body');
        while ($lo <= $maxtalkid) {
            print "  talk ($lo - $hi, of $maxtalkid)\n" if $optv > 1;
            foreach my $table (keys %cols) {
                $sth = $dbo->prepare("SELECT $cols{$table} FROM $table ".
                                     "WHERE journalid=$userid AND jtalkid BETWEEN $lo AND $hi");
                $sth->execute;
                while (my @vals = $sth->fetchrow_array) {
                    LJ::text_compress(\$vals[3]) if $table eq "talktext2";
                    $write->("$table:($cols{$table})", @vals);
                }
            }
            
            $hi += $load_amt; $lo += $load_amt;
        }
    }

    # talkleft table.  
    {
        # no primary key... delete all of target first.
        while ($dbch->do("DELETE FROM talkleft WHERE userid=$userid LIMIT 1000") > 0) {
            print "  deleted from talkleft\n" if $optv > 1;
        }

        my $last_max = 0;
        my $cols = "userid,posttime,journalid,nodetype,nodeid,jtalkid,publicitem";
        while (defined $last_max) {
            print "  talkleft: $last_max\n" if $optv > 1;
            my $sth = $dbo->prepare("SELECT $cols FROM talkleft WHERE userid=$userid ".
                                    "AND posttime > $last_max ORDER BY posttime LIMIT 1000");
            $sth->execute;
            undef $last_max;
            while (my @vals = $sth->fetchrow_array) {
                $write->("talkleft:($cols)", @vals);
                $last_max = $vals[1];
            }
        }
    }

    # flush remaining items
    foreach (keys %pendreplace) { $flush->($_); }

    # unset readonly and move to new cluster in one update
    LJ::update_user($userid, { clusterid => $dclust, raw => "caps=caps&~(1<<$readonly_bit)" });
    print "Moved.\n" if $optv;

    # delete from source cluster
    if ($opt_del) {
        print "Deleting from source cluster...\n" if $optv;
        foreach my $table (sort keys %$pri_key) {
            my $pri = $pri_key->{$table};
            while ($dbo->do("DELETE FROM $table WHERE $pri=$userid LIMIT 500") > 0) {
                print "  deleted from $table\n" if $optv;
            }
        }

        # s1stylecache table
        if (@styleids) {
            my $styleids_in = join(",", map { $dbo->quote($_) } @styleids);
            if ($dbo->do("DELETE FROM s1stylecache WHERE styleid IN ($styleids_in)") > 0) {
                print "  deleted from s1stylecache\n" if $optv;
            }
        }
    } else {
        # at minimum, we delete the clustertrack2 row so it doesn't get
        # included in a future ljumover.pl query from that cluster.
        $dbo->do("DELETE FROM clustertrack2 WHERE userid=$userid");
    }

    $dbh->do("UPDATE clustermove SET sdeleted=?, timedone=UNIX_TIMESTAMP() ".
             "WHERE cmid=?", undef, $opt_del ? 1 : 0, $cmid);
    exit 0;
}

sub deletefrom0_logitem
{
    my $itemid = shift;

    # delete all the comments
    my $talkids = $dbh->selectcol_arrayref("SELECT talkid FROM talk ".
                                           "WHERE nodetype='L' AND nodeid=$itemid");

    my $talkidin = join(",", @$talkids);
    if ($talkidin) {
        foreach my $table (qw(talktext talkprop talk)) {
            $dbh->do("DELETE FROM $table WHERE talkid IN ($talkidin)");
        }
    }

    $dbh->do("DELETE FROM logsec WHERE ownerid=$userid AND itemid=$itemid");
    foreach my $table (qw(logprop logtext log)) {
        $dbh->do("DELETE FROM $table WHERE itemid=$itemid");
    }
}

sub movefrom0_logitem
{
    my $itemid = shift;

    my $item = $bufread->(100, "SELECT * FROM log", $itemid);
    my $itemtext = $bufread->(50, "SELECT itemid, subject, event FROM logtext", $itemid);
    return 1 unless $item && $itemtext;   # however that could happen.

    # we need to allocate a new jitemid (journal-specific itemid) for this item now.
    my $jitemid = $alloc_id->('L', $itemid);
    unless ($jitemid) {
        die "ERROR: could not allocate a new jitemid\n";
    }
    $dbh->{'RaiseError'} = 1;
    $item->{'jitemid'} = $jitemid;
    $item->{'anum'} = int(rand(256));

    # copy item over:
    $replace_into->("log2", "(journalid, jitemid, posterid, eventtime, logtime, ".
                    "compressed, security, allowmask, replycount, year, month, day, ".
                    "rlogtime, revttime, anum)",
                    50, map { $item->{$_} } qw(ownerid jitemid posterid eventtime
                                               logtime compressed security allowmask replycount
                                               year month day rlogtime revttime anum));

    $replace_into->("logtext2", "(journalid, jitemid, subject, event)", 10,
                    $userid, $jitemid, map { $itemtext->{$_} } qw(subject event));

    # add disk usage info!  (this wasn't in cluster0 anywhere)
    my $bytes = length($itemtext->{'event'}) + length($itemtext->{'subject'});
    $replace_into->("dudata", "(userid, area, areaid, bytes)", 50, $userid, 'L', $jitemid, $bytes);

    # add the logsec item, if necessary:
    if ($item->{'security'} ne "public") {
        $replace_into->("logsec2", "(journalid, jitemid, allowmask)", 50,
                        map { $item->{$_} } qw(ownerid jitemid allowmask));
    }

    # copy its logprop over:
    while (my $lp = $bufread->(50, "SELECT itemid, propid, value FROM logprop", $itemid)) {
        next unless $lp->{'value'};
        $replace_into->("logprop2", "(journalid, jitemid, propid, value)", 50,
                        $userid, $jitemid, $lp->{'propid'}, $lp->{'value'});
    }

    # copy its talk shit over:
    my %newtalkids = (0 => 0);  # 0 maps back to 0 still
    my $talkids = $dbr->selectcol_arrayref("SELECT talkid FROM talk ".
                                           "WHERE nodetype='L' AND nodeid=$itemid");
    my @talkids = sort { $a <=> $b } @$talkids;
    my $treader = make_buffer_reader("talkid", \@talkids);
    foreach my $t (@talkids) {
        movefrom0_talkitem($t, $jitemid, \%newtalkids, $item, $treader);
    }
}

sub movefrom0_talkitem
{
    my $talkid = shift;
    my $jitemid = shift;
    my $newtalkids = shift;
    my $logitem = shift;
    my $treader = shift;

    my $item = $treader->(100, "SELECT *, UNIX_TIMESTAMP(datepost) AS 'datepostunix' FROM talk", $talkid);
    my $itemtext = $treader->(50, "SELECT talkid, subject, body FROM talktext", $talkid);
    return 1 unless $item && $itemtext;   # however that could happen.

    # abort if this is a stranded entry.  (shouldn't happen, anyway.  even if it does, it's 
    # not like we're losing data:  the UI (talkread.bml) won't show it anyway)
    return unless defined $newtalkids->{$item->{'parenttalkid'}};

    # we need to allocate a new jitemid (journal-specific itemid) for this item now.
    my $jtalkid = $alloc_id->('T', $talkid);
    unless ($jtalkid) {
        die "ERROR: could not allocate a new jtalkid\n";
    }
    $newtalkids->{$talkid} = $jtalkid;
    $dbh->{'RaiseError'} = 1;

    # copy item over:
    $replace_into->("talk2", "(journalid, jtalkid, parenttalkid, nodeid, ".
                    "nodetype, posterid, datepost, state)", 50,
                    $userid, $jtalkid, $newtalkids->{$item->{'parenttalkid'}},
                    $jitemid, 'L',  map { $item->{$_} } qw(posterid datepost state));


    $replace_into->("talktext2", "(journalid, jtalkid, subject, body)",
                    20, $userid, $jtalkid, map { $itemtext->{$_} } qw(subject body));

    # copy its logprop over:
    while (my $lp = $treader->(50, "SELECT talkid, tpropid, value FROM talkprop", $talkid)) {
        next unless $lp->{'value'};
        $replace_into->("talkprop2", "(journalid, jtalkid, tpropid, value)", 50,
                        $userid, $jtalkid, $lp->{'tpropid'}, $lp->{'value'});
    }

    # note that poster commented here
    if ($item->{'posterid'}) {
        my $pub = $logitem->{'security'} eq "public" ? 1 : 0;
        my ($table, $db) = ("talkleft_xfp", $dbh);
        ($table, $db) = ("talkleft", $dbch) if $userid == $item->{'posterid'};
        $replace_into->($db, $table, "(userid, posttime, journalid, nodetype, ".
                        "nodeid, jtalkid, publicitem)", 50,
                        $item->{'posterid'}, $item->{'datepostunix'}, $userid,
                        'L', $jitemid, $jtalkid, $pub);
    }
}

sub make_buffer_reader
{
    my $pricol = shift;
    my $valsref = shift;

    my %bfd;  # buffer read data.  halfquery -> { 'rows' => { id => [] },
              #                                   'remain' => [], 'loaded' => { id => 1 } }
    return sub
    {
        my ($amt, $hq, $pid) = @_;
        if (not defined $bfd{$hq}->{'loaded'}->{$pid})
        {
            if (not exists $bfd{$hq}->{'remain'}) {
                $bfd{$hq}->{'remain'} = [ @$valsref ];
            }

            my @todo;
            for (1..$amt) {
                next unless @{$bfd{$hq}->{'remain'}};
                my $id = shift @{$bfd{$hq}->{'remain'}};
                push @todo, $id;
                $bfd{$hq}->{'loaded'}->{$id} = 1;
            }

            if (@todo) {
                my $sql = "$hq WHERE $pricol IN (" . join(",", @todo) . ")";
                my $sth = $dbr->prepare($sql);
                $sth->execute;
                while (my $r = $sth->fetchrow_hashref) {
                    push @{$bfd{$hq}->{'rows'}->{$r->{$pricol}}}, $r;
                }
            }
        }

        return shift @{$bfd{$hq}->{'rows'}->{$pid}};
    };
}

# this function needs to die loudly if moveucluster.pl is unable to move
# any type of table that exists on this installation
sub verify_movable_tables {
    my %table;  # tablename -> unhandled flag

    # first, assume everything's unhandled
    foreach my $t (@LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL) {
        $table{$t} = 1;
    }

    # now, clear things we know how to move
    foreach my $t (qw(cmdbuffer dudata log2 logsec2 logprop2 logtext2
                      talk2 talkprop2 talktext2 talkleft
                      ), @manual_move) {
        delete $table{$t};
    }

    # local stuff
    my $local_tables = LJ::run_hook("moveucluster_local_tables");
    if ($local_tables) {
        while (my ($tab, $key) = each %$local_tables) {
            delete $table{$tab};
        }
    }

    # things we list as active tables but don't use yet
    delete $table{"events"};

    # things we don't move because it doesn't really matter
    delete $table{"s1stylecache"};
    delete $table{"captcha_session"};

    if (%table) {
        die "ERROR.  Won't try to move user, because this mover script can't move all live tables for this user.  List of tables without mover code available: \n -- " . join("\n -- ", sort keys %table), "\n";
    }

}

1; # return true;
