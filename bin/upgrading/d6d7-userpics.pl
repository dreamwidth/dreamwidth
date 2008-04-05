#!/usr/bin/perl
#

use strict;
use Getopt::Long;
$| = 1;

use lib "$ENV{'LJHOME'}/cgi-bin/";
require "ljlib.pl";
use LJ::Blob;
use LJ::User;

use constant DEBUG => 0;  # turn on for debugging (mostly db handle crap)

my $BLOCK_MOVE   = 5000;  # user rows to get at a time before moving
my $BLOCK_INSERT =   25;  # rows to insert at a time when moving users
my $BLOCK_UPDATE = 1000;  # users to update at a time if they had no data to move

# get options
my %opts;
exit 1 unless
    GetOptions("lock=s" => \$opts{locktype},
               "user=s" => \$opts{user},
               "total=i" => \$opts{total},);
              

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
    return 0 unless $u->{'dversion'} == 6;

    # at this point, try to get a lock for this user
    my $lock;
    if ($opts{locktype} eq 'ddlockd') {
        $lock = LJ::locker()->trylock("d6d7-$u->{user}");
        return 1 unless $lock;
    }

    # get a handle for every user to revalidate our connection?
    my ($dbh, $dbcm) = $get_db_handles->($u->{clusterid});
    return 0 unless $dbh;

    # assign this dbcm to the user
    if ($dbcm) {
        $u->set_dbcm($dbcm)
            or die "unable to set database for $u->{user}: dbcm=$dbcm\n";
    }

    # verify dversion hasn't changed on us (done by another job?)
    my $dversion = $dbh->selectrow_array("SELECT dversion FROM user WHERE userid = $u->{userid}");
    return 1 unless $dversion == 6;

    # ignore expunged users
    if ($u->{'statusvis'} eq "X" || $u->{'clusterid'} == 0) {
        LJ::update_user($u, { dversion => 7 })
            or die "error updating dversion";
        $u->{dversion} = 7; # update local copy in memory
        return 1;
    }

    return 0 unless $dbcm;

    # step 0.5: delete all the bogus userblob rows for this user
    # This is due to the auto_increment for the blobid overflowing
    # and thus all entries recieving an id of max id for a mediumint.
    # This is lame.
    my $domainid = LJ::get_blob_domainid('userpic');
    $u->do("DELETE FROM userblob WHERE journalid=$u->{userid} AND domain=$domainid AND blobid>=16777216");
    die "error in delete: " . $u->errstr . "\n" if $u->err;

    # step 1: get all user pictures and move those.  safe to just grab with no limit
    # since users can only have a limited number of them
    my $rows = $dbh->selectall_arrayref('SELECT picid, userid, contenttype, width, height, state, picdate, md5base64 ' .
                                        'FROM userpic WHERE userid = ?', undef, $u->{userid}) || [];

    if (@$rows) {
        # got some rows, create an update statement
        my (@bind, @vars, @blobids, @blobbind, @picinfo);
        foreach my $row (@$rows) {
            my $picid = $row->[0];
            push @bind, "(?, ?, ?, ?, ?, ?, ?, ?)";

            $row->[2] = {'image/gif' => 'G',
                         'image/jpeg' => 'J',
                         'image/png' => 'P'}->{$row->[2]};
            push @vars, @$row;

            # [picid, fmt]
            my $fmt = {'G' => 'gif',
                       'J' => 'jpg',
                       'P' => 'png'}->{$row->[2]};
            push @picinfo, [$picid, $fmt];

            # picids
            push @blobids, $picid;
            push @blobbind, "?";
        }

        my $bind = join ',', @bind;
        $u->do("REPLACE INTO userpic2 (picid, userid, fmt, width, height, state, picdate, md5base64) " .
               "VALUES $bind", undef, @vars);
        die "error in userpic2 replace: " . $u->errstr . "\n" if $u->err;

        # step 1.5: insert missing rows into the userblob table
        my $blobbind = join ',', @blobbind;
        my $blobrows = $dbcm->selectall_hashref("SELECT blobid FROM userblob WHERE journalid=$u->{userid} AND domain=$domainid " .
                                                "AND blobid IN ($blobbind)", 'blobid', undef, @blobids) || {};

        my (@insertbind, @insertvars);
        foreach my $pic (@picinfo) {
            my ($picid, $fmt) = @$pic;
            unless ($blobrows->{$picid}) {
                push @insertbind, "(?, ?, ?, ?)";

                my $blob = LJ::Blob::get($u, "userpic", $fmt, $picid);
                my $length = length($blob);

                push @insertvars, $u->{'userid'}, $domainid, $picid, $length;
            }
        }
        if (@insertbind) {
            my $insertbind = join ',', @insertbind;
            $u->do("INSERT IGNORE INTO userblob (journalid, domain, blobid, length) " .
                   "VALUES $insertbind", undef, @insertvars);
            die "error in userblob insert: " . $u->errstr . "\n" if $u->err;
        }
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

    # step 2: get the mapping of all of their keywords
    my $kwrows = $dbh->selectall_arrayref('SELECT picid, kwid FROM userpicmap WHERE userid=?',
                                          undef, $u->{'userid'});
    my %kwmap;
    if (@$kwrows) {
        push @{$kwmap{$_->[1]}}, $_->[0] foreach @$kwrows; # kwid -> [ picid, picid, picid ... ]
    }

    # step 3: get the actual keywords associated with these keyword ids
    my %kwidmap;
    if (%kwmap) {
        my $kwids = join ',', map { $_+0 } keys %kwmap;
        my $rows = $dbh->selectall_arrayref("SELECT kwid, keyword FROM keywords WHERE kwid IN ($kwids)");
        %kwidmap = map { $_->[0] => $_->[1] } @$rows; # kwid -> keyword
    }

    # step 4: now migrate all keywords into userkeywords table
    my %mappings;
    while (my ($kwid, $keyword) = each %kwidmap) {
        # reallocate counter
        my $newkwid = LJ::get_keyword_id($u, $keyword);
        die "Error: unable to get keyword id for $u->{user}($u->{userid}), keyword '$keyword'\n"
            unless $newkwid;
        $mappings{$kwid} = $newkwid;
    }

    # step 5: now we have to do some mapping conversions and put new data into userpicmap2 table
    while (my ($oldkwid, $picids) = each %kwmap) {
        foreach my $picid (@$picids) {
            # get new data
            my $newkwid = $mappings{$oldkwid};

            # push data
            push @bind, "($u->{userid}, ?, ?)";
            push @vars, ($picid, $newkwid);

            # flush?
            $flush->('userpicmap2', 'userid, picid, kwid')
                if @bind > $BLOCK_INSERT;
        }
    }
    $flush->('userpicmap2', 'userid, picid, kwid');

    # delete memcache keys that hold old data
    LJ::MemCache::delete([$u->{userid}, "upicinf:$u->{userid}"]);

    # haven't died yet?  everything is still going okay, so update dversion
    LJ::update_user($u, { 'dversion' => 7 })
        or die "error updating dversion";
    $u->{'dversion'} = 7; # update local copy in memory

    return 1;
};

# get dbh handle
my $dbh = LJ::get_db_writer(); # just so we can get users...
die "Could not connect to global master" unless $dbh;

# get user count
my $total = $opts{total} || $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion = 6");
$stats{'total_users'} = $total+0;

# print out header and total we're moving
print $header->("Moving user data");
print "Processing $stats{'total_users'} total users with the old dversion\n";

# loop until we have no more users to convert
my $ct;
while (1) {
    # get users to move
    my $sth;
    if ($opts{user}) {
        $sth = $dbh->prepare("SELECT * FROM user WHERE user = ? AND dversion = 6");
        $sth->execute($opts{user});
    } else {
        $sth = $dbh->prepare("SELECT * FROM user WHERE dversion = 6 LIMIT $BLOCK_MOVE");
        $sth->execute();
    }

    # get blocks of $BLOCK_MOVE users at a time
    $ct = 0;
    my (%us, %fast);
    while (my $u = $sth->fetchrow_hashref()) {
        $us{$u->{userid}} = $u;
        $fast{$u->{userid}} = 1;
        $ct++;
    }

    # jump out if we got nothing
    last unless $ct;

    # now that we have %us, we can see who has data
    my $ids = join ',', map { $_+0 } keys %us;
    my $has_upics = $dbh->selectcol_arrayref("SELECT DISTINCT userid FROM userpic WHERE userid IN ($ids)");
    my %uids = ( map { $_ => 1 } (@$has_upics) );

    # remove folks that have userpics from the fast list
    delete $fast{$_} foreach keys %uids;

    # now see who we can do in a fast way
    my @fast_ids = map { $_+0 } keys %fast;
    if (@fast_ids) {
        # update stats for counting and print
        $stats{'fast_moved'} += @fast_ids;
        print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users");

        # block update
        LJ::update_user(\@fast_ids, { dversion => 7 });
    }
    
    my $slow_todo = scalar keys %uids;
    print "Of $BLOCK_MOVE, $slow_todo have to be slow-converted...\n";
    my @ids = randlist(keys %uids);
    foreach my $id (@ids) {
        # this person has userpics, move them the slow way
        die "Userid $id in \$has_upics, but not in \%us...fatal error\n" unless $us{$id};

        # now move the user
        bless $us{$id}, 'LJ::User';
        if ($move_user->($us{$id})) {
            $stats{'slow_moved'}++;
            print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users", $us{$id}{user});
        }
    }

}

# ...done?
print $header->("Dversion 6->7 conversion completed");
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
