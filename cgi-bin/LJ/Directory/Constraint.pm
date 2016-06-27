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

package LJ::Directory::Constraint;
use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);

use LJ::Directory::SetHandle;

use LJ::Directory::Constraint::Age;
use LJ::Directory::Constraint::Interest;
use LJ::Directory::Constraint::UpdateTime;
use LJ::Directory::Constraint::Trusts;
use LJ::Directory::Constraint::TrustedBy;
use LJ::Directory::Constraint::Watches;
use LJ::Directory::Constraint::WatchedBy;
use LJ::Directory::Constraint::MemberOf;
use LJ::Directory::Constraint::Location;
use LJ::Directory::Constraint::JournalType;
use LJ::Directory::Constraint::Test;

use DW::BlobStore;

sub constraints_from_formargs {
    my ($pkg, $postargs) = @_;

    my @ret;
    foreach my $type (qw(Age Location UpdateTime Interest Trusts TrustedBy Watches WatchedBy MemberOf JournalType)) {
       my $class = "LJ::Directory::Constraint::$type";
       my $con = eval { $class->new_from_formargs($postargs) };
       if ( ref $con eq 'ARRAY' ) {
           push @ret, @$con;
       } elsif ( $con ) {
           push @ret, $con;
       } elsif ($@) {
           warn "Error loading constraint $type: $@";
       }

    }
    return @ret;
}

sub deserialize {
    my ($pkg, $str) = @_;
    $str =~ s/^(.+?):// or return undef;
    my $type = $1;
    my %args = map { LJ::durl($_) } split(/[=&]/, $str);
    return bless \%args, "LJ::Directory::Constraint::$type";
}

sub serialize {
    my $self = shift;
    my $type = ref $self;
    $type =~ s/^LJ::Directory::Constraint:://;
    return "$type:" . join("&",
                           map { LJ::eurl($_) . "=" . LJ::eurl($self->{$_}) }
                           grep { /^[a-z]/ && $self->{$_} }
                           sort
                           keys %$self);
}

# default is one minute, should override in subclasses
sub cache_for {
    my $self = shift;
    return 60;
}

# digest of canonicalized $self
sub cache_key {
    my $self = shift;
    return $self->{cache_key} ||= sha1_hex($self->serialize);
}

# returns memcache key to find this's constraint's sethandle, if cached
sub memkey {
    my $self = shift;
    return "dsh:" . $self->cache_key;
}

# returns cached sethandle if it exists, otherwise undef
sub cached_sethandle {
    my $self = shift;

    # check memcache to see if there is a sethandle
    my $seth_serialized = LJ::MemCache::get($self->memkey);
    if ($seth_serialized) {
        my $seth = LJ::Directory::SetHandle->new_from_string($seth_serialized);
        return $seth;
    }

    # no handle in memcache, check dirmogsethandles table to see if there
    # is a mogile handle for us
    my $dbr = LJ::get_db_reader() or die "Could not get DB reader";
    my ($exptime) = $dbr->selectrow_array("SELECT exptime FROM dirmogsethandles WHERE conskey=?",
                                          undef, $self->cache_key);
    die "For $self: " . $dbr->errstr if $dbr->err;

    if ($exptime) {
        # there is an entry for this, make sure it isn't expired
        if ($exptime > time()) {
            # not expired, return mogile sethandle, should be valid
            return LJ::Directory::SetHandle::Mogile->new($self->cache_key);
        } # otherwise it's expired, ignore it
    }

    return undef;
}

# test cache first, return sethandle, or generate set, and return sethandle.
sub sethandle {
    my $self = shift;

    my $cached = $self->cached_sethandle;
    return $cached if $cached;

    my $cachekey = $self->cache_key;

    my @uids = $self->matching_uids;
    my $seth;

    if (@uids <= 4000) {
        $seth = LJ::Directory::SetHandle::Inline->new(@uids);
    } else {
        my $dbh = LJ::get_db_writer()
            or die "Could not get db writer";

        # register this mogile key
        $dbh->do("REPLACE INTO dirmogsethandles (conskey, exptime) VALUES (?, UNIX_TIMESTAMP()+?)",
                 undef, $cachekey, ($self->cache_for || 0));
        die $dbh->errstr if $dbh->err;

        my $content = join( '', map { pack("N*", $_) } @uids );
        DW::BlobStore->store( directorysearch => "dsh:$cachekey", \$content );

        $seth = LJ::Directory::SetHandle::Mogile->new($cachekey);
    }

    # put in memcache:
    LJ::MemCache::set($self->memkey,
                      $seth->as_string,
                      $self->cache_for);

    return $seth;
}

sub matching_uids {
    my $self = shift;
    die "matching_uids not implemented on $self";
}

# override in subclasses
# return expected cardinality of this constraint, between 0 and 1
sub cardinality { 0 }

1;
