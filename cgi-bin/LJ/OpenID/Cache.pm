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

package LJ::OpenID::Cache;
use strict;

my $important = qr/^(?:hassoc|shandle):/;

sub new {
    my $class = shift;
    return bless { memc => LJ::MemCache::get_memcache(), }, $class;
}

sub get {
    my ( $self, $key ) = @_;

    # try memcached first.
    my $val = $self->{memc}->get($key);
    return $val if $val;

    # important keys, on miss, try the database.
    if ( $key =~ /$important/ ) {
        my $dbh = LJ::get_db_writer();
        $val = $dbh->selectrow_array( "SELECT value FROM blobcache WHERE bckey=?", undef, $key )
            or return undef;

        # put it back in memcache.
        my $rv = $self->{memc}->set( $key, $val );
        return $val;
    }

    return undef;
}

sub set {
    my ( $self, $key, $val ) = @_;

    # important keys go to the database
    if ( $key =~ /$important/ ) {
        my $dbh = LJ::get_db_writer();
        $dbh->do( "REPLACE INTO blobcache SET bckey=?, dateupdate=NOW(), value=?",
            undef, $key, $val );
    }

    # everything goes in memcache.
    $self->{memc}->set( $key, $val );
}

1;
