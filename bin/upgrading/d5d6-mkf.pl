#!/usr/bin/perl
#

use strict;
use Getopt::Long;
$| = 1;

use lib ("$ENV{LJHOME}/cgi-bin");
require "ljlib.pl";
use LJ::User;

use constant DEBUG => 0;  # turn on for debugging (mostly db handle crap)

my $BLOCK_MOVE   = 5000;  # user rows to get at a time before moving
my $BLOCK_INSERT =   25;  # rows to insert at a time when moving users
my $BLOCK_UPDATE = 1000;  # users to update at a time if they had no data to move

# get options
my %opts;
exit 1 unless
    GetOptions("lock=s" => \$opts{locktype},);

# if no locking, notify them about it
die "ERROR: Lock must be of types 'ddlockd' or 'none'\n"
    if $opts{locktype} && $opts{locktype} !~ m/^(?:ddlockd|none)$/;

# used for keeping stats notes
my %stats = (); # { 'stat' => 'value' }

my %handle;

# database handle retrieval sub
my $get_db_handles = sub {
    # figure out what cluster to load
    my $cid = shift(@_) + 0;

    my $dbh = $handle{0};
    unless ($dbh) {
        $dbh = $handle{0} = LJ::get_dbh({ raw => 1 }, "master");
        print "Connecting to master ($dbh)...\n";
        eval {
            $dbh->do("SET wait_timeout=28800");
        };
        $dbh->{'RaiseError'} = 1;
    }
    
    my $dbcm;
    $dbcm = $handle{$cid} if $cid;
    if ($cid && ! $dbcm) {
        $dbcm = $handle{$cid} = LJ::get_cluster_master({ raw => 1 }, $cid);
        print "Connecting to cluster $cid ($dbcm)...\n";
        return undef unless $dbcm;
        eval {
            $dbcm->do("SET wait_timeout=28800");
        };
        $dbcm->{'RaiseError'} = 1;
    }
    
    # return one or both, depending on what they wanted
    return $cid ? ($dbh, $dbcm) : $dbh;
};

# percentage complete
my $status = sub {
    my ($ct, $tot, $units, $user) = @_;
    my $len = length($tot);

    my $usertxt = $user ? " Moving user: $user" : '';
    return sprintf(" \[%6.2f%%: %${len}d/%${len}d $units]$usertxt\n",
                   ($ct / $tot) * 100, $ct, $tot);
};

my $header = sub {
    my $size = 50;
    return "\n" .
           ("#" x $size) . "\n" .
           "# $_[0] " . (" " x ($size - length($_[0]) - 4)) . "#\n" .
           ("#" x $size) . "\n\n";
};

my $zeropad = sub {
    return sprintf("%d", $_[0]);
};

# mover function
my $move_user = sub {
    my $u = shift;

    # make sure our user is of the proper dversion
    return 0 unless $u->{'dversion'} == 5;

    # at this point, try to get a lock for this user
    my $lock;
    if ($opts{locktype} eq 'ddlockd') {
        $lock = LJ::locker()->trylock("d5d6-$u->{user}");
        return 1 unless $lock;
    }

    # get a handle for every user to revalidate our connection?
    my ($dbh, $dbcm) = $get_db_handles->($u->{clusterid});
    return 0 unless $dbh;

    if ($dbcm) {
        # assign this dbcm to the user
        $u->set_dbcm($dbcm)
            or die "unable to set database for $u->{user}: dbcm=$dbcm\n";
    }

    # verify dversion hasn't changed on us (done by another job?)
    my $dversion = $dbh->selectrow_array("SELECT dversion FROM user WHERE userid = $u->{userid}");
    return 1 unless $dversion == 5;

    # ignore expunged users
    if ($u->{'statusvis'} eq "X" || $u->{'clusterid'} == 0) {
        LJ::update_user($u, { dversion => 6 })
            or die "error updating dversion";
        $u->{dversion} = 6; # update local copy in memory
        return 1;
    }

    return 0 unless $dbcm;

    # step 1: get all friend groups and move those.  safe to just grab with no limit because
    # there are limits to how many friend groups you can have (30).
    my $rows = $dbh->selectall_arrayref('SELECT groupnum, groupname, sortorder, is_public ' .
                                        'FROM friendgroup WHERE userid = ?', undef, $u->{userid});
    if (@$rows) {
        # got some rows, create an update statement
        my (@bind, @vars);
        foreach my $row (@$rows) {
            push @bind, "($u->{userid}, ?, ?, ?, ?)";
            push @vars, $_ foreach @$row;
        }
        my $bind = join ',', @bind;
        eval {
            $u->do("INSERT INTO friendgroup2 (userid, groupnum, groupname, sortorder, is_public) " .
                   "VALUES $bind", undef, @vars);
        };
    }

    # general purpose flusher for use below
    my (@bind, @vars);
    my $flush = sub {
        return unless @bind;
        my ($table, $cols) = @_;

        # insert data into cluster master
        my $bind = join(",", @bind);
        $u->do("REPLACE INTO $table ($cols) VALUES $bind", undef, @vars);
        die "error in flush $table: " . $u->errstr . "\n" if $u->err;

        # reset values
        @bind = ();
        @vars = ();
    };

    # step 1.5: see if the user has any data already? clear it if so.
    my $counter = $dbcm->selectrow_array("SELECT max FROM counter WHERE journalid = ? AND area = 'R'",
                                         undef, $u->{userid});
    $counter += 0;
    if ($counter > 0) {
        # yep, so we need to delete stuff, real data first
        foreach my $table (qw(memorable2 memkeyword2 userkeywords)) {
            $u->do("DELETE FROM $table WHERE userid = ?", undef, $u->{userid});
            die "error in clear: " . $u->errstr . "\n" if $u->err;
        }

        # delete counters used (including memcache of such)
        $u->do("DELETE FROM counter WHERE journalid = ? AND area IN ('R', 'K')", undef, $u->{userid});
        die "error in clear: " . $u->errstr . "\n" if $u->err;
        LJ::MemCache::delete([$u->{userid}, "auc:$u->{userid}:R"]);
        LJ::MemCache::delete([$u->{userid}, "auc:$u->{userid}:K"]);
    }

    # step 2: get all of their memories and move them, creating the oldmemid -> newmemid mapping
    # that we can use in later steps to migrate keywords
    my %bindings; # ( oldid => newid )
    my $sth = $dbh->prepare('SELECT memid, journalid, jitemid, des, security ' .
                            'FROM memorable WHERE userid = ?');
    $sth->execute($u->{userid});
    while (my $row = $sth->fetchrow_hashref()) {
        # got a row, good
        my $newid = LJ::alloc_user_counter($u, 'R');
        die "Error: unable to allocate type 'R' counter for $u->{user}($u->{userid})\n"
            unless $newid;
        $bindings{$row->{memid}} = $newid;

        # push data
        push @bind, "($u->{userid}, ?, ?, ?, ?, ?)";
        push @vars, ($newid, map { $row->{$_} } qw(journalid jitemid des security));

        # flush if necessary
        $flush->('memorable2', 'userid, memid, journalid, ditemid, des, security')
            if @bind > $BLOCK_INSERT;
    }
    $flush->('memorable2', 'userid, memid, journalid, ditemid, des, security');

    # step 3: get the list of keywords that these memories all use
    my %kwmap;
    if (%bindings) {
        my $memids = join ',', map { $_+0 } keys %bindings;
        my $rows = $dbh->selectall_arrayref("SELECT memid, kwid FROM memkeyword WHERE memid IN ($memids)");
        push @{$kwmap{$_->[1]}}, $_->[0] foreach @$rows; # kwid -> [ memid, memid, memid ... ]
    }

    # step 4: get the actual keywords associated with these keyword ids
    my %kwidmap;
    if (%kwmap) {
        my $kwids = join ',', map { $_+0 } keys %kwmap;
        my $rows = $dbh->selectall_arrayref("SELECT kwid, keyword FROM keywords WHERE kwid IN ($kwids)");
        %kwidmap = map { $_->[0] => $_->[1] } @$rows; # kwid -> keyword
    }

    # step 5: now migrate all keywords into userkeywords table
    my %mappings;
    while (my ($kwid, $keyword) = each %kwidmap) {
        # reallocate counter
        my $newkwid = LJ::alloc_user_counter($u, 'K');
        die "Error: unable to allocate type 'K' counter for $u->{user}($u->{userid})\n"
            unless $newkwid;
        $mappings{$kwid} = $newkwid;

        # push data
        push @bind, "($u->{userid}, ?, ?)";
        push @vars, ($newkwid, $keyword);

        # flush if necessary
        $flush->('userkeywords', 'userid, kwid, keyword')
            if @bind > $BLOCK_INSERT;
    }
    $flush->('userkeywords', 'userid, kwid, keyword');

    # step 6: now we have to do some mapping conversions and put new data into memkeyword2 table
    while (my ($oldkwid, $oldmemids) = each %kwmap) {
        foreach my $oldmemid (@$oldmemids) {
            # get new data
            my ($newkwid, $newmemid) = ($mappings{$oldkwid}, $bindings{$oldmemid});

            # push data
            push @bind, "($u->{userid}, ?, ?)";
            push @vars, ($newmemid, $newkwid);

            # flush?
            $flush->('memkeyword2', 'userid, memid, kwid')
                if @bind > $BLOCK_INSERT;
        }
    }
    $flush->('memkeyword2', 'userid, memid, kwid');

    # delete memcache keys that hold old data
    LJ::MemCache::delete([$u->{userid}, "memkwid:$u->{userid}"]);

    # haven't died yet?  everything is still going okay, so update dversion
    LJ::update_user($u, { 'dversion' => 6 })
        or die "error updating dversion";
    $u->{'dversion'} = 6; # update local copy in memory

    return 1;
};

# get dbh handle
my $dbh = LJ::get_db_writer(); # just so we can get users...
die "Could not connect to global master" unless $dbh;

# get user count
my $total = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion = 5");
$stats{'total_users'} = $total+0;

# print out header and total we're moving
print $header->("Moving user data");
print "Processing $stats{'total_users'} total users with the old dversion\n";

# loop until we have no more users to convert
my $ct;
while (1) {

    # get blocks of $BLOCK_MOVE users at a time
    my $sth = $dbh->prepare("SELECT * FROM user WHERE dversion = 5 LIMIT $BLOCK_MOVE");
    $sth->execute();
    $ct = 0;
    my %us;

    my %fast;  # people to move fast

    while (my $u = $sth->fetchrow_hashref()) {
        $us{$u->{userid}} = $u;
        $ct++;
        $fast{$u->{userid}} = 1;
    }

    # jump out if we got nothing
    last unless $ct;

    # now that we have %us, we can see who has data
    my $ids = join ',', map { $_+0 } keys %us;
    my $has_memorable = $dbh->selectcol_arrayref("SELECT DISTINCT userid FROM memorable WHERE userid IN ($ids)");
    my $has_fgroups = $dbh->selectcol_arrayref("SELECT DISTINCT userid FROM friendgroup WHERE userid IN ($ids)");
    my %uids = ( map { $_ => 1 } (@$has_memorable, @$has_fgroups) );

    # these people actually have data to migrate; don't move them fast
    delete $fast{$_} foreach keys %uids;

    # now see who we can do in a fast way
    my @fast_ids = map { $_+0 } keys %fast;
    if (@fast_ids) {
        print "Converting ", scalar(@fast_ids), " users quickly...\n";
        # update stats for counting and print
        $stats{'fast_moved'} += @fast_ids;
        print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users");

        # block update
        LJ::update_user(\@fast_ids, { dversion => 6 });
    }

    my $slow_todo = scalar keys %uids;
    print "Of $BLOCK_MOVE, $slow_todo have to be slow-converted...\n";
    my @ids = randlist(keys %uids);
    foreach my $id (@ids) {
        # this person has memories, move them the slow way
        die "Userid $id in \$has_memorable, but not in \%us...fatal error\n" unless $us{$id};

        # now move the user
        bless $us{$id}, 'LJ::User';
        if ($move_user->($us{$id})) {
            $stats{'slow_moved'}++;
            print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users", $us{$id}{user});
        }

    }

}

# ...done?
print $header->("Dversion 5->6 conversion completed");
print "  Users moved: " . $zeropad->($stats{'slow_moved'}) . "\n";
print "Users updated: " . $zeropad->($stats{'fast_moved'}) . "\n\n";

# helper function to randomize stuff
sub randlist
{
    my @rlist = @_;
    my $size = scalar(@rlist);
    
    my $i;
    for ($i=0; $i<$size; $i++) {
        unshift @rlist, splice(@rlist, $i+int(rand()*($size-$i)), 1);
    }
    return @rlist;
}
