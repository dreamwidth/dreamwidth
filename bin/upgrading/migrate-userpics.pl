#!/usr/bin/perl
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
BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}
use LJ::User;
use LJ::Userpic;
use DW::BlobStore;

use Getopt::Long;
use IPC::Open3;
use Digest::MD5;
use Log::Log4perl;

# this script is a migrater that will move userpics from an old storage method
# into whatever blobstore method is defined in the site config.

# the basic theory is that we iterate over all clusters, find all userpics that
# aren't in either mogile or blobstore right now, and put them in blobstore

# determine
my ($one, $besteffort, $dryrun, $user, $verify, $verbose, $clusters, $purge);
my $rv = GetOptions("best-effort"  => \$besteffort,
                    "one"          => \$one,
                    "dry-run"      => \$dryrun,
                    "user=s"       => \$user,
                    "verify"       => \$verify,
                    "verbose"      => \$verbose,
                    "purge-old"    => \$purge,
                    "clusters=s"   => \$clusters,);
unless ($rv) {
    die <<ERRMSG;
This script supports the following command line arguments:

    --clusters=X[-Y]
        Only handle clusters in this range.  You can specify a
        single number, or a range of two numbers with a dash.

    --user=username
        Only move this particular user.

    --one
        Only move one user.  (But it moves all their pictures.)
        This is used for testing.

    --verify
        If specified, this option will reload the userpic from
        BlobStore and make sure it's been stored successfully.

    --dry-run
        If on, do not update the database.  This mode will put
        the userpic in BlobStore and let you examine the image
        and make sure everything is okay.  It will not update the
        userpic2 table, though.

    --best-effort
        Normally, if a problem is encountered (null userpic, md5
        mismatch, connection failure, etc) the script will die to
        make sure everything goes well.  With this flag, we don't
        die and instead just print to standard error.

    --purge-old
        Sometimes we run into data that is for users that have since
        moved to a different cluster.  Normally we ignore it, but
        with this option, we'll clean that data up as we find it.

    --verbose
        Be very chatty.
ERRMSG
}

# make sure ljconfig is setup right (or so we hope)
die "Please define \@LJ::BLOBSTORES in your site config\n"
    unless @LJ::BLOBSTORES && scalar @LJ::BLOBSTORES;

# setup stderr if we're in best effort mode
if ($besteffort) {
    my $oldfd = select(STDERR);
    $| = 1;
    select($oldfd);
}

# use a custom log4perl config, to make sure we're getting
# DEBUG messages from Blobstore if we've requested verbose
# output, but not under normal use

my $conf = 'log4perl.rootLogger=' . ( $verbose ? 'DEBUG' : 'ERROR' );
$conf .= q{, STDERR

log4perl.appender.STDERR=Log::Log4perl::Appender::Screen
log4perl.appender.STDERR.stderr=1
log4perl.appender.STDERR.layout=Log::Log4perl::Layout::SimpleLayout
};
Log::Log4perl::init( \$conf );

# operation modes
if ($user) {
    # move a single user
    my $u = LJ::load_user($user);
    die "No such user: $user\n" unless $u;
    handle_userid($u->{userid}, $u->{clusterid});

} else {
    # parse the clusters
    my @clusters;
    if ($clusters) {
        if ($clusters =~ /^(\d+)(?:-(\d+))?$/) {
            my ($min, $max) = map { $_ + 0 } ($1, $2 || $1);
            push @clusters, $_ foreach $min..$max;
        } else {
            die "Error: --clusters argument not of right format.\n";
        }
    } else {
        @clusters = @LJ::CLUSTERS;
    }

    # now iterate over the clusters to pick
    my $ctotal = scalar(@clusters);
    my $ccount = 0;
    foreach my $cid (sort { $a <=> $b } @clusters) {
        # status report
        $ccount++;
        print "\nChecking cluster $cid...\n\n";

        # get a handle
        my $dbcm = get_db_handle($cid);

        # get all userids
        print "Getting userids...\n";
        my $limit = $one ? 'LIMIT 1' : '';
        my $userids = $dbcm->selectcol_arrayref
            ("SELECT DISTINCT userid FROM userpic2 WHERE (location <> 'mogile' AND location <> 'blobstore') OR location IS NULL $limit");
        my $total = scalar(@$userids);

        # iterate over userids
        my $count = 0;
        print "Beginning iteration over userids...\n";
        foreach my $userid (@$userids) {
            # move this userpic
            my $extra = sprintf("[%6.2f%%, $ccount of $ctotal] ", (++$count/$total*100));
            handle_userid($userid, $cid, $extra);
        }

        # don't hit up more clusters
        last if $one;
    }
}
print "\n";

print "Updater terminating.\n";

#############################################################################
### helper subs down here

# take a userid and move their pictures.  returns 0 on error, 1 on successful
# move of a user's pictures, and 2 meaning the user isn't ready for moving
# (dversion < 7, etc)
sub handle_userid {
    my ($userid, $cid, $extra) = @_;

    # load user to move and do some sanity checks
    my $u = LJ::load_userid($userid);
    unless ($u) {
        LJ::end_request();
        LJ::start_request();
        $u = LJ::load_userid($userid);
    }
    die "ERROR: Unable to load userid $userid\n"
        unless $u;

    # if they're expunged, they might have data somewhere if they were
    # copy-moved from A to B, then expunged on B.  now we're on A and
    # need to delete it ourselves (if purge-old is on)
    if ( $u->{clusterid} == 0 && $u->is_expunged ) {
        return unless $purge;
        # if we get here, the user has indicated they want data purged, get handle
        my $to_purge_dbcm = get_db_handle($cid);
        my $ct = $to_purge_dbcm->do("DELETE FROM userpic2 WHERE userid = ?", undef, $u->{userid});
        print "\tnotice: purged $ct old rows.\n\n"
            if $verbose;
        return;
    }

    # get a handle
    my $dbcm = get_db_handle($u->{clusterid});

    # print that we're doing this user
    print "$extra$u->{user}($u->{userid})\n";

    # if a user has been moved to another cluster, but the source data from
    # userpic2 wasn't deleted, we need to ignore the user or purge their data
    if ($u->{clusterid} != $cid) {
        return unless $purge;

        # verify they have some rows on the new side
        my $count = $dbcm->selectrow_array
            ("SELECT COUNT(*) FROM userpic2 WHERE userid = ?",
             undef, $u->{userid});
        return unless $count;

        # if we get here, the user has indicated they want data purged, get handle
        my $to_purge_dbcm = get_db_handle($cid);

        # delete the old data
        if ($dryrun) {
            print "\tnotice: need to delete userpic2 rows.\n\n"
                if $verbose;
        } else {
            my $ct = $to_purge_dbcm->do("DELETE FROM userpic2 WHERE userid = ?", undef, $u->{userid});
            print "\tnotice: purged $ct old rows.\n\n"
                if $verbose;
        }

        # nothing else to do here
        return;
    }

    # get all their photos that aren't in mogile or blobstore already
    my $picids = $dbcm->selectall_arrayref
        ("SELECT picid, md5base64, fmt, location FROM userpic2 WHERE userid = ? AND ( (location <> 'mogile' AND location <> 'blobstore') OR location IS NULL )",
         undef, $u->{userid});
    return unless @$picids;

    # now we have a userid and picids, get the photos from the blob server
    foreach my $row (@$picids) {
        my ($picid, $md5, $fmt, $loc) = @$row;
        print "\tstarting move for picid $picid\n"
            if $verbose;

        my $format = { G => 'gif', J => 'jpg', P => 'png' }->{$fmt};

        my $data;

        # no target?  then it's in the database
        unless ( defined $loc ) {

            ($data) = $dbcm->selectrow_array(
                'SELECT imagedata FROM userpicblob2 WHERE userid = ? AND picid = ?',
                undef, $u->{userid}, $picid
            );

        }

        # get length
        my $len = length($data);
        if ($besteffort && !$len) {
            print STDERR "empty_userpic userid=$u->{userid} picid=$picid\n";
            print "\twarning: empty userpic.\n\n"
                if $verbose;
            next;
        }
        die "Error: data from location=$loc empty ($u->{user}, 'userpic', $format, $picid)\n"
            unless $len;

        # verify the md5 of this picture with what's in the database
        my $blobmd5 = Digest::MD5::md5_base64($data);
        if ($besteffort && ($md5 ne $blobmd5)) {
            print STDERR "md5_mismatch userid=$u->{userid} picid=$picid dbmd5=$md5 blobmd5=$blobmd5\n";
            print "\twarning: md5 mismatch; database=$md5, blobserver=$blobmd5\n\n"
                if $verbose;
            next;
        }
        die "\tError: data from blobserver md5 mismatch: database=$md5, blobserver=$blobmd5\n"
            unless $md5 eq $blobmd5;
        print "\tverified md5; database=$md5, blobserver=$blobmd5\n"
            if $verbose;

        # get filehandle to blobstore and put the file there
        print "\tdata length = $len bytes, uploading to BlobStore...\n"
            if $verbose;
        my $storage_key = LJ::Userpic->storage_key( $u->userid, $picid );
        my $bstore = DW::BlobStore->store( userpics => $storage_key, \$data );
        if ( $besteffort && !$bstore ) {
            print STDERR "store_failed userid=$u->{userid} picid=$picid\n";
            print "\twarning: failed in call to store\n\n"
                if $verbose;
            next;
        }
        die "Unable to store file in BlobStore\n"
            unless $bstore;

        # extra verification
        if ($verify) {
            my $data2 = DW::BlobStore->retrieve( userpics => $storage_key );
            my $eq = ($data2 && $$data2 eq $data) ? 1 : 0;
            if ($besteffort && !$eq) {
                print STDERR "verify_failed userid=$u->{userid} picid=$picid\n";
                print "\twarning: verify failed; picture not updated\n\n"
                    if $verbose;
                next;
            }
            die "\tERROR: picture NOT stored successfully, content mismatch\n"
                unless $eq;
            print "\tverified length = " . length($$data2) . " bytes...\n"
                if $verbose;
        }

        # done moving this picture
        unless ($dryrun) {
            print "\tupdating database for this picture...\n"
                if $verbose;
            $dbcm->do("UPDATE userpic2 SET location = 'blobstore' WHERE userid = ? AND picid = ?",
                      undef, $u->{userid}, $picid);
        }

        # get the paths so the user can verify if they want
        if ($verbose) {
            # Log4perl will print the blobstore path when in
            # debug mode, no need to calculate it again here
            print "\tverify site url: $LJ::SITEROOT/userpic/$picid/$u->{userid}\n";
            print "\tpicture update complete.\n\n";
        }
    }
}

# a sub to get a cluster handle and set it up for our use
sub get_db_handle {
    my $cid = shift;

    my $dbcm = LJ::get_cluster_master({ raw => 1 }, $cid);
    unless ($dbcm) {
        print STDERR "handle_unavailable clusterid=$cid\n";
        die "ERROR: unable to get raw handle to cluster $cid\n";
    }
    eval {
        $dbcm->do("SET wait_timeout = 28800");
        die $dbcm->errstr if $dbcm->err;
    };
    die "Couldn't set wait_timeout on $cid: $@\n" if $@;
    $dbcm->{'RaiseError'} = 1;

    return $dbcm;
}
