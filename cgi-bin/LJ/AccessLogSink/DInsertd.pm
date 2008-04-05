package LJ::AccessLogSink::DInsertd;
use strict;
use base 'LJ::AccessLogSink';

sub new {
    my ($class, %opts) = @_;
    return bless {}, $class;
}

sub log {
    my ($self, $rec) = @_;

    my @dinsertd_socks;
    my $now = time();

    foreach my $hostport (@LJ::DINSERTD_HOSTS) {
        next if $LJ::CACHE_DINSERTD_DEAD{$hostport} > $now - 15;

        my $sock =
            $LJ::CACHE_DINSERTD_SOCK{$hostport} ||=
            IO::Socket::INET->new(PeerAddr => $hostport,
                                  Proto    => 'tcp',
                                  Timeout  => 1,
                                  );

        if ($sock) {
            delete $LJ::CACHE_DINSERTD_DEAD{$hostport};
            push @dinsertd_socks, [ $hostport, $sock ];
        } else {
            delete $LJ::CACHE_DINSERTD_SOCK{$hostport};
            $LJ::CACHE_DINSERTD_DEAD{$hostport} = $now;
        }
    }
    return 0 unless @dinsertd_socks;

    my $hash = {
        _table => $rec->table,
    };
    $hash->{$_} = $rec->{$_} foreach $rec->keys;

    my $string = "INSERT " . Storable::freeze($hash) . "\r\n";
    my $len = "\x01" . substr(pack("N", length($string) - 2), 1, 3);
    $string = $len . $string;

    foreach my $sr (@dinsertd_socks) {
        my $sock = $sr->[1];
        print $sock $string;
        my $rin;
        my $res;
        vec($rin, fileno($sock), 1) = 1;
        $res = <$sock> if select($rin, undef, undef, 0.3);
        delete $LJ::CACHE_DINSERTD_SOCK{$sr->[0]} unless $res =~ /^OK\b/;
    }

}

1;
