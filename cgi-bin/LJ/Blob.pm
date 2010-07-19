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
#
# Wrapper around BlobClient.

package LJ::Blob;
use strict;
use BlobClient;
use BlobClient::Local;

my %bc_cache = ();
my %bc_reader_cache = ();
my %bc_path_reader_cache = ();

# read-write (i.e. HTTP connection to BlobServer, with NetApp NFS mounted)
sub get_blobclient {
    my $u = shift;
    my $bcid = $u->{blob_clusterid} or die "No blob_clusterid";
    return $bc_cache{$bcid} ||=
        _bc_from_path($LJ::BLOBINFO{clusters}->{$bcid},
                      $LJ::BLOBINFO{clusters}->{"$bcid-BACKUP"});
}

# read-only access.  (i.e. direct HTTP connection to NetApp)
sub get_blobclient_reader {
    my $u = shift;
    my $bcid = $u->{blob_clusterid} or die "No blob_clusterid";

    return $bc_reader_cache{$bcid} if $bc_reader_cache{$bcid};

    my $path = $LJ::BLOBINFO{clusters}->{"$bcid-GET"} ||
        $LJ::BLOBINFO{clusters}->{$bcid};
    my $bpath = $LJ::BLOBINFO{clusters}->{"$bcid-BACKUP"};

    return $bc_reader_cache{$bcid} = _bc_from_path($path, $bpath);
}

sub _bc_from_path {
    my ($path, $bpath) = @_;
    if ($path =~ /^http/) {
        die "BlobClient::Remote support is now removed in favor of MogileFS.";
    } elsif ($path) {
        return BlobClient::Local->new({ path => $path });
    }
    return undef;
}

# given a $u, returns that user's blob_clusterid, conditionally loading it
sub _load_bcid {
    my $u = shift;
    die "No user" unless LJ::isu( $u );
    return $u->{blob_clusterid} if $u->{blob_clusterid};

    return $u->prop( "blob_clusterid" )
        or die "Couldn't find user $u->{user}'s blob_clusterid\n";
}

# args: u, domain, fmt, bid
# des-fmt: string file extension ("jpg", "gif", etc)
# des-bid: numeric blob id for this domain
# des-domain: string name of domain ("userpic", "phonephost", etc)
sub get {
    my ($u, $domain, $fmt, $bid) = @_;
    _load_bcid($u);
    my $bc = get_blobclient_reader($u);
    return $bc->get($u->{blob_clusterid}, $u->{userid}, $domain, $fmt, $bid);
}

# Return a path relative to the specified I<root> for the given arguments.
# args: root, u, domain, fmt, bid
# des-root: Root path
# des-fmt: string file extension ("jpg", "gif", etc)
# des-bid: numeric blob id for this domain
# des-domain: string name of domain ("userpic", "phonephost", etc)
sub get_rel_path {
    my ( $root, $u, $domain, $fmt, $bid ) = @_;

    my $bcid = _load_bcid( $u );
    my $bc = $bc_path_reader_cache{ "$bcid:$root" } ||= new BlobClient::Local ({ path => $root });

    return $bc->make_path( $bcid, $u->{userid}, $domain, $fmt, $bid );
}


sub get_stream {
    my ($u, $domain, $fmt, $bid, $callback) = @_;
    _load_bcid($u);
    my $bc = get_blobclient_reader($u);
    return $bc->get_stream($u->{blob_clusterid}, $u->{userid}, $domain, $fmt, $bid, $callback);
}

sub put {
    my ($u, $domain, $fmt, $bid, $data, $errref) = @_;
    _load_bcid($u);
    my $bc = get_blobclient($u);

    unless ($u->writer) {
        $$errref = "nodb";
        return 0;
    }

    unless ($bc->put($u->{blob_clusterid}, $u->{userid}, $domain,
                     $fmt, $bid, $data, $errref)) {
        return 0;
    }

    $u->do("INSERT IGNORE INTO userblob (journalid, domain, blobid, length) ".
           "VALUES (?, ?, ?, ?)", undef,
           $u->{userid}, LJ::get_blob_domainid($domain),
           $bid, length($data));
    die "Error doing userblob accounting: " . $u->errstr if $u->err;
    return 1;
}

sub delete {
    my ($u, $domain, $fmt, $bid) = @_;
    _load_bcid($u);
    my $bc = get_blobclient($u);

    return 0 unless $u->writer;

    my $bdid = LJ::get_blob_domainid($domain);
    return 0 unless $bc->delete($u->{blob_clusterid}, $u->{userid}, $domain,
                                $fmt, $bid);

    $u->do("DELETE FROM userblob WHERE journalid=? AND domain=? AND blobid=?",
           undef, $u->{userid}, $bdid, $bid);
    die "Error doing userblob accounting: " . $u->errstr if $u->err;
    return 1;
}

sub get_disk_usage {
    shift @_ unless LJ::isu($_[0]);  # let it be called as class method (LJ::Blob->get_disk_usage($u,...))
    my ($u, $domain) = @_;
    my $dbcr = LJ::get_cluster_reader($u);
    if ($domain) {
        return $dbcr->selectrow_array("SELECT SUM(length) FROM userblob ".
                                      "WHERE journalid=? AND domain=?", undef,
                                      $u->{userid}, LJ::get_blob_domainid($domain));
    } else {
        return $dbcr->selectrow_array("SELECT SUM(length) FROM userblob ".
                                      "WHERE journalid=?", undef, $u->{userid});
    }
}

1;
