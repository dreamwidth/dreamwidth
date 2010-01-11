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
