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

package Apache::SendStats;

BEGIN {
    $LJ::HAVE_AVAIL = eval "use Apache::Availability qw(count_servers); 1;";
}

use strict;
use IO::Socket::INET;
use Apache2::Const qw/ :common /;
use Socket qw(SO_BROADCAST);

our %udp_sock;

sub handler {
    my $apache_r = shift;
    return OK if $apache_r->main;
    return OK unless $LJ::HAVE_AVAIL && $LJ::FREECHILDREN_BCAST;

    my $callback  = $apache_r ? $apache_r->current_callback() : "";
    my $cleanup   = $callback eq "PerlCleanupHandler";
    my $childinit = $callback eq "PerlChildInitHandler";

    if ($LJ::TRACK_URL_ACTIVE) {
        my $key = "url_active:$LJ::SERVER_NAME:$$";
        if ($cleanup) {
            LJ::MemCache::delete($key);
        }
        else {
            LJ::MemCache::set( $key,
                      $apache_r->header_in("Host")
                    . $apache_r->uri . "("
                    . $apache_r->method . "/"
                    . scalar( $apache_r->args )
                    . ")" );
        }
    }

    my ( $active, $free ) = count_servers();

    $free += $cleanup;
    $free += $childinit;
    $active -= $cleanup if $active;

    my $list = ref $LJ::FREECHILDREN_BCAST ? $LJ::FREECHILDREN_BCAST : [$LJ::FREECHILDREN_BCAST];

    foreach my $host (@$list) {
        next unless $host =~ /^(\S+):(\d+)$/;
        my $bcast = $1;
        my $port  = $2;
        my $sock  = $udp_sock{$host};
        unless ($sock) {
            $udp_sock{$host} = $sock = IO::Socket::INET->new( Proto => 'udp' );
            if ($sock) {
                $sock->sockopt( SO_BROADCAST, 1 )
                    if $LJ::SENDSTATS_BCAST;
            }
            else {
                $apache_r->log_error("SendStats: couldn't create socket: $host");
                next;
            }
        }

        my $ipaddr   = inet_aton($bcast);
        my $portaddr = sockaddr_in( $port, $ipaddr );
        my $message  = "bcast_ver=1\nfree=$free\nactive=$active\n";
        my $res      = $sock->send( $message, 0, $portaddr );
        $apache_r->log_error("SendStats: couldn't broadcast")
            unless $res;
    }

    return OK;
}

1;
