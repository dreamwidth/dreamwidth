#!/usr/bin/perl
#

use strict;
$| = 1;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $BLOCK_MOVE   = 5000;  # user rows to get at a time before moving
my $BLOCK_INSERT =   25;  # rows to insert at a time when moving users
my $BLOCK_UPDATE = 1000;  # users to update at a time if they had no data to move

# used for keeping stats notes
my %stats = (); # { 'action' => { 'pass' => { 'stat' => 'value' } } }

# rows come order by user, keep last username so we can avoid dups
my $lastuser;

# what pass are we on?
my $pass;

my $get_db_writer = sub {
    return LJ::get_dbh({raw=>1}, "master");
};

my $get_db_slow = sub {
    return LJ::get_dbh({raw=>1}, "slow", "master");
};

my $get_cluster_master = sub {
    my $cid = shift;
    return LJ::get_dbh({raw=>1}, "cluster$cid");
};

# percentage complete
my $status = sub {
    my ($ct, $tot, $units, $pass, $user) = @_;
    my $len = length($tot);

    my $passtxt = $pass ? "[Pass: $pass] " : '';
    my $usertxt = $user ? " Moving user: $user" : '';
    return sprintf(" $passtxt\[%6.2f%%: %${len}d/%${len}d $units]$usertxt\n",
                   ($ct / $tot) * 100, $ct, $tot);
};

my $header = sub {
    my $size = 50;
    return "\n" .
           ("#" x $size) . "\n" .
           "# $_[0] " . (" " x ($size - length($_[0]) - 4)) . "#\n" .
           ("#" x $size) . "\n\n";
};

# mover function
my $move_user = sub {
    my $user = shift;

    # if the current user is the same as the last,
    # we have a duplicate so skip it
    return 0 if $user eq $lastuser;
    $lastuser = $user;

    my $u = LJ::load_user($user);
    return 0 unless $u->{'dversion'} == 4;

    # update user count for this pass
    $stats{'move'}->{$pass}->{'user_ct'}++;

    # print status
    print $status->($stats{'move'}->{$pass}->{'ct'},
                    $stats{'move'}->{$pass}->{'total'}, "rows", $pass, $user);

    # ignore expunged users
    if ($u->{'statusvis'} eq "X") {
	LJ::update_user($u, { 'dversion' => 5 })
	    or die "error updating dversion";
	$u->{'dversion'} = 5; # update local copy in memory
	return 1;
    }

    # get a handle for every user to revalidate our connection?
    my $dbh = $get_db_writer->()
        or die "Can't connect to global master";
    my $dbslo = $get_db_slow->()
        or die "Can't connect to global slow master";
    my $dbcm = $get_cluster_master->($u->{'clusterid'})
        or die "Can't connect to cluster master ($u->{'clusterid'})";

    # be careful, we're moving data
    foreach my $db ($dbh, $dbslo, $dbcm) {
	$db->do("SET wait_timeout=28800");
	$db->{'RaiseError'} = 1;
    }

    my @map = (['style' => 's1style',
                qw(styleid userid styledes type formatdata is_public 
                   is_embedded is_colorfree opt_cache has_ads lastupdate) ],
               ['overrides' => 's1overrides',
                qw(userid override) ]
               );

    # in moving, s1stylecache gets special cased because its
    # name hasn't changed, only location. so if there is only
    # one cluster, then there's no point in physically moving it

    if (@LJ::CLUSTERS > 1) {
        push @map, ['s1stylecache' => 's1stylecache',
                    qw(styleid cleandate type opt_cache vars_stor vars_cleanver) ];
    }
    
    # user 'system' is a special case.  if we encounter this user we'll swap $dbcm
    # to secretly be a $dbh.  because the 'system' user uses the clustered tables
    # on the global dbs, the queries will still work, we just need to misdirect them
    $dbcm = $dbh if $u->{'user'} eq 'system';

    # styleids to delete since s1stylemap isn't keyed on user
    my @delete_styleids = ();

    # update tables
    foreach my $tableinf (@map) {

        # find src and dest table names
        my $src_table  = shift @$tableinf;
        my $dest_table = shift @$tableinf;

        # if this is the style table, replace into stylemap here,
        # so that if this process is killed, style and stylemap
        # won't get too out of sync
        my $do_stylemap = $src_table eq 'style' && $dest_table eq 's1style';

        # find what columns this table has
        my @cols = @$tableinf;
        my $cols = join(",", @cols);
        my $bind_row = "(" . join(",", map { "?" } @cols) . ")";

        my (@bind, @vals);
        my (@map_bind, @map_vals);

        # flush rows to destination table
        my $flush = sub {
            return unless @bind;

            # insert data
            my $bind = join(",", @bind);
            $dbcm->do("REPLACE INTO $dest_table ($cols) VALUES $bind", undef, @vals);

            # insert new styles into s1stylemap
            if ($do_stylemap) {
                my $map_bind = join(",", @map_bind);
                $dbh->do("REPLACE INTO s1stylemap (styleid, userid) VALUES $map_bind",
                         undef, @map_vals);
            }

            # reset values
            @bind = ();
            @vals = ();
        };

        # s1stylecache is the only table keyed on styleid, not user
        my $where = "user=" . $dbh->quote($u->{'user'});
        if ($src_table eq "s1stylecache") {
            my $ids = $dbh->selectcol_arrayref("SELECT styleid FROM style WHERE user=?",
					       undef, $u->{'user'});
            my $ids_in = join(",", map { $dbh->quote($_) } @$ids) || "0";
            $where = "styleid IN ($ids_in)";
        }

        # select from source table and build data for insert
        my $sth = $dbh->prepare("SELECT * FROM $src_table WHERE $where");
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref) {

            # so that when we look for userid later, it'll be there
            $row->{'userid'} = $u->{'userid'};

            # build data for insert
            push @bind, $bind_row;
            push @vals, $row->{$_} foreach @cols;

            # special case: insert new s1styles into s1stylemap
            if ($do_stylemap) {
                push @map_bind, "(?,?)";
                push @map_vals, ($row->{'styleid'}, $u->{'userid'});
                push @delete_styleids, $row->{'styleid'};
            }

            # increment the count for this pass, style or overrides
            $stats{'move'}->{$pass}->{'ct'}++
                unless $src_table eq 's1stylecache';

            # flush if we've reached our insert limit
            $flush->() if @bind > $BLOCK_INSERT;
        }

        $flush->();
    }

    # haven't died yet?  everything is still going okay

    # update dversion
    LJ::update_user($u, { 'dversion' => 5 })
        or die "error updating dversion";
    $u->{'dversion'} = 5; # update local copy in memory

    return 1;
};

my $dbh = $get_db_writer->();
die "Could not connect to global master" unless $dbh;
$dbh->{'RaiseError'} = 1;
my $dbslo = $get_db_slow->();
die "Could not connect to global slow master" unless $dbslo;
$dbslo->{'RaiseError'} = 1;

my $ts = $dbslo->selectrow_hashref("SHOW TABLE STATUS LIKE 'overrides'");
if ($ts->{'Type'} eq 'ISAM') {
    die "This script isn't efficient with ISAM tables.  Please convert to MyISAM with:\n" .
        "   mysql> ALTER TABLE overrides TYPE=MyISAM;\n\n" .
        "Then re-run this script.\n";
}

print $header->("Moving user data");

# first pass should get everything, second pass will
# get changes made during the first
foreach my $p (1..2) {

    # this is strange.  perl bug?
    $pass = $p;

    # get totals from overrides and style so we can do a percentage bar
    # there will be overlaps in this when users have both styles and 
    # overrides, but we'll fix those up as we go
    foreach (qw(style overrides)) {
        $stats{'move'}->{$pass}->{'total'} += $dbslo->selectrow_array("SELECT COUNT(*) FROM $_");
    }

    print "Processing $stats{'move'}->{$p}->{'total'} total rows\n";

    # 2 passes, so we catch people with styles & overrides,
    # styles w/o overrides, and overrides w/o styles
    foreach my $table (qw(style overrides)) {

        $lastuser = '';

        # loop until we have no more users to convert
        my $ct;
        do {

            # get blocks of $BLOCK_MOVE users at a time
            my $sth = $dbslo->prepare("SELECT user FROM $table WHERE user>? " .
                                      "ORDER BY user LIMIT $BLOCK_MOVE");
            $sth->execute($lastuser);
            $ct = 0;
            while (my $user = $sth->fetchrow_array) {
                $move_user->($user);
                $ct++;
            }

        } while $ct;
    }

    print $stats{'move'}->{$p}->{'user_ct'}+0 . " users moved\n\n";
}

# now we're confident that all users have had their data moved if
# necessary, so we can just unconditionally change dversions.

print $header->("Updating remaining users");

$stats{'update'}->{'total'} = $dbslo->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion=4");
print "Converting $stats{'update'}->{'total'} users\n";

# now update dversions for users who had no data to move
if ($stats{'update'}->{'total'}) {

    my $get_users = sub {
        my $sth = $dbslo->prepare("SELECT userid, user FROM user " .
                                "WHERE dversion=4 LIMIT $BLOCK_UPDATE");
        $sth->execute();
        my @rows; # [ userid, user ]
        while ( my ($userid, $user) = $sth->fetchrow_array) {
            push @rows, [ $userid, $user ];
        }
        return @rows;
    };

    while (my @rows = $get_users->()) {

        # update database
        my $bind = join(",", map { "?" } @rows);
        my @vals = map { $_->[0] } @rows;
        $dbh->do("UPDATE user SET dversion=5 WHERE userid IN ($bind)",
                 undef, @vals);

        # update memcache
        foreach (@rows) {
            LJ::MemCache::delete([$_->[0], "userid:" . $_->[0]]);
            LJ::MemCache::delete([$_->[1], "user:"   . $_->[1]]);
        }
        $stats{'update'}->{'ct'} += @rows;

        print $status->($stats{'update'}->{'ct'}, $stats{'update'}->{'total'}, "users");
    }
}

my $zeropad = sub {
    return sprintf("%d", $_[0]);
};

# calculate total move stats
foreach (1..2) {
    $stats{'move'}->{'total_ct'} += $stats{'move'}->{$_}->{'ct'};
    $stats{'move'}->{'total_user_ct'} += $stats{'move'}->{$_}->{'user_ct'};
}

print $header->("Dversion 4->5 conversion completed");
print "   Rows moved: " . $zeropad->($stats{'move'}->{'total_ct'}) . "\n";
print "  Users moved: " . $zeropad->($stats{'move'}->{'total_user_ct'}) . "\n";
print "Users updated: " . $zeropad->($stats{'update'}->{'ct'}) . "\n\n";
