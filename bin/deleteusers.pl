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

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
my $dbh = LJ::get_dbh("master");
$dbh->{'RaiseError'} = 1;
$dbh->{'PrintError'} = 1;
my $sth;

$sth = $dbh->prepare("SELECT userid FROM user WHERE statusvis='D' AND statusvisdate < DATE_SUB(NOW(), INTERVAL 60 DAY) LIMIT 1000");
$sth->execute;
my @delusers;
while (my $duid = $sth->fetchrow_array) {
    push @delusers, $duid;
}
print "Users to delete: ", scalar(@delusers), "\n";

# Get hashref mapping {userid => $u} for all users to be deleted
my $user = LJ::load_userids(@delusers);

LJ::load_props($dbh, "talk");
my $p_delposter = LJ::get_prop("talk", "deleted_poster");
die "No 'deleted_poster' talkprop?" unless $p_delposter;
my $ids;

my $lastbreak = time();
my $pause = sub {
    if (time() - $lastbreak > 3) { print "pause.\n"; sleep(1); $lastbreak = time(); }
};

# FIXME: This will soon need to be changed to use methods of the $u
#    object rather than global LJ:: functions, but this should work
#    for now.

my $runsql = sub {
    my $db = $dbh;
    if (ref $_[0]) { $db = shift; }
    my $user = shift;
    my $sql = shift;
    print "  ($user) $sql\n";
    $db->do($sql);
};

my $czero = 0;

foreach my $uid (@delusers)
{
    my $du = $user->{$uid};
    my $user = $du->{'user'};
    print "$du->{'user'} ($du->{'userid'}) @ $du->{'statusvisdate'}";
    if ($du->{clusterid} == 0) {
        print " (on clusterid 0; skipping)\n";
        $czero++;
        next;
    }
    print " (cluster $du->{'clusterid'})...\n";
    $pause->();

    # get a db handle for the cluster master.
    LJ::start_request(); # might've been awhile working with last handle, we don't want to be given an expired one.
    my $dbcm = LJ::get_cluster_master($du);
    $dbcm->{'RaiseError'} = 1;
    $dbcm->{'PrintError'} = 1;

    # make all the user's comments posted now be owned by posterid 0 (anonymous)
    # but with meta-data saying who used to own it
    # ..... hm, with clusters this is a pain.  let's not.

    # delete userpics
    {
        print "  userpics\n";
        $ids = $dbcm->selectcol_arrayref("SELECT picid FROM userpic2 WHERE userid=$uid");
        my $in = join(",",@$ids);
        if ($in) {
            print "  userpics: $in\n";
            $runsql->($dbcm, $user, "DELETE FROM userpicblob2 WHERE userid=$uid AND picid IN ($in)");
            $runsql->($dbcm, $user, "DELETE FROM userpic2 WHERE userid=$uid");
            $runsql->($dbcm, $user, "DELETE FROM userpicmap2 WHERE userid=$uid");
            $runsql->($dbcm, $user, "DELETE FROM userkeywords WHERE userid=$uid");
        }
    }

    # delete posts
    print "  posts\n";
    while (($ids = $dbcm->selectall_arrayref("SELECT jitemid, anum FROM log2 WHERE journalid=$uid LIMIT 100")) && @{$ids})
    {
        foreach my $idanum (@$ids) {
            my ($id, $anum) = ($idanum->[0], $idanum->[1]);
            print "  deleting $id (a=$anum) ($uid; $du->{'user'})\n";
            LJ::delete_entry($du, $id, 0, $anum);
            $pause->();
        }
    }

    # misc:
    $runsql->($user, "DELETE FROM userusage WHERE userid=$uid");
    $runsql->($user, "DELETE FROM wt_edges WHERE from_userid=$uid");
    $runsql->($user, "DELETE FROM wt_edges WHERE to_userid=$uid");
    $runsql->($dbcm, $user, "DELETE FROM trust_groups WHERE userid=$uid");
    $runsql->($dbcm, $user, "DELETE FROM memorable2 WHERE userid=$uid");
    $runsql->($dbcm, $user, "DELETE FROM userkeywords WHERE userid=$uid");
    $runsql->($dbcm, $user, "DELETE FROM memkeyword2 WHERE userid=$uid");
    $runsql->($user, "DELETE FROM userbio WHERE userid=$uid");
    $runsql->($dbcm, $user, "DELETE FROM userbio WHERE userid=$uid");
    $runsql->($user, "DELETE FROM userinterests WHERE userid=$uid");
    $runsql->($user, "DELETE FROM userprop WHERE userid=$uid");
    $runsql->($user, "DELETE FROM userproplite WHERE userid=$uid");
    $runsql->($user, "DELETE FROM txtmsg WHERE userid=$uid");
    $runsql->($user, "DELETE FROM overrides WHERE user='$du->{'user'}'");
    $runsql->($user, "DELETE FROM priv_map WHERE userid=$uid");
    $runsql->($user, "DELETE FROM infohistory WHERE userid=$uid");
    $runsql->($user, "DELETE FROM reluser WHERE userid=$uid");
    $runsql->($user, "DELETE FROM reluser WHERE targetid=$uid");
    $runsql->($user, "DELETE FROM userlog WHERE userid=$uid");

    $runsql->($user, "UPDATE user SET statusvis='X', statusvisdate=NOW(), password='' WHERE userid=$uid");

}

if ($czero) {
    print "\nWARNING: There are $czero users on cluster zero pending deletion.\n";
    print "  These users must be upgraded before they can be expunged with this tool.\n";
}
