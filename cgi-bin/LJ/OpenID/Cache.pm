package LJ::OpenID::Cache;
use strict;

my $important = qr/^(?:hassoc|shandle):/;

sub new {
    my $class = shift;
    return bless {
        memc => LJ::MemCache::get_memcache(),
    }, $class;
}

sub get {
    my ($self, $key) = @_;

    # try memcached first.
    my $val = $self->{memc}->get($key);
    return $val if $val;

    # important keys, on miss, try the database.
    if ($key =~ /$important/) {
        my $dbh = LJ::get_db_writer();
        $val = $dbh->selectrow_array("SELECT value FROM blobcache WHERE bckey=?", undef, $key)
            or return undef;
        # put it back in memcache.
        my $rv = $self->{memc}->set($key, $val);
        return $val;
    }

    return undef;
}

sub set {
    my ($self, $key, $val) = @_;

    # important keys go to the database
    if ($key =~ /$important/) {
        my $dbh = LJ::get_db_writer();
        $dbh->do("REPLACE INTO blobcache SET bckey=?, dateupdate=NOW(), value=?",
                 undef, $key, $val);
    }

    # everything goes in memcache.
    $self->{memc}->set($key, $val);
}

1;
