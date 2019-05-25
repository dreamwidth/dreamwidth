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

package Apache::DebateSuicide;

use strict;
use Apache2::Const qw/ :common /;
use LJ::ModuleCheck;

our ( $gtop, %known_parent, $ppid );

# oh btw, this is totally linux-specific.  gtop didn't work, so so much for portability.
sub handler {
    my $apache_r = shift;
    return OK if $apache_r->main;
    return OK unless $LJ::SUICIDE && LJ::ModuleCheck->have("GTop");

    my $meminfo;
    return OK unless open( MI, "/proc/meminfo" );
    $meminfo = join( '', <MI> );
    close MI;

    my %meminfo;
    while ( $meminfo =~ m/(\w+):\s*(\d+)\skB/g ) {
        $meminfo{$1} = $2;
    }

    my $memfree = $meminfo{'MemFree'} + $meminfo{'Cached'};
    return OK unless $memfree;

    my $goodfree = $LJ::SUICIDE_UNDER{$LJ::SERVER_NAME} || $LJ::SUICIDE_UNDER || 150_000;
    my $is_under = $memfree < $goodfree;

    my $maxproc = $LJ::SUICIDE_OVER{$LJ::SERVER_NAME} || $LJ::SUICIDE_OVER || 1_000_000;
    my $is_over = 0;

    $gtop ||= GTop->new;

    # if $is_under, we know we'll be exiting anyway, so no need
    # to continue to check $maxproc
    unless ($is_under) {

        # find out how much memory we are using
        my $pm          = $gtop->proc_mem($$);
        my $proc_size_k = ( $pm->rss - $pm->share ) >> 10;    # config is in KB

        $is_over = $proc_size_k > $maxproc;
    }
    return OK unless $is_over || $is_under;

    # we'll proceed to die if we're one of the largest processes
    # on this machine

    unless ($ppid) {
        my $self = pid_info($$);
        $ppid = $self->[3];
    }

    my $pids = child_info($ppid);
    my @pids = keys %$pids;

    my %stats;
    my $sum_uniq = 0;
    foreach my $pid (@pids) {
        my $pm = $gtop->proc_mem($pid);
        $stats{$pid} = [ $pm->rss - $pm->share, $pm ];
        $sum_uniq += $stats{$pid}->[0];
    }

    @pids = ( sort { $stats{$b}->[0] <=> $stats{$a}->[0] } @pids, 0, 0 );

    if ( grep { $$ == $_ } @pids[ 0, 1 ] ) {
        my $my_use_k = $stats{$$}[0] >> 10;
        if ( $LJ::DEBUG{'suicide'} ) {
            $apache_r->log_error( "Suicide [$$]: system memory free = ${memfree}k; "
                    . "i'm big, using ${my_use_k}k" );
        }

        # we should have logged by here, but be paranoid in any case
        Apache::LiveJournal::db_logger($apache_r) unless $apache_r->pnotes('did_lj_logging');

        # This is supposed to set MaxChildRequests to 1, then clear the
        # KeepAlive flag so that Apache will terminate after this request,
        # but it doesn't work.  We'll call it here just in case.
        $apache_r->child_terminate;

        # We should call Apache::exit(Apache::Constants::DONE) here because
        # it makes sure that the child shuts down cleanly after fulfilling
        # its request and running logging handlers, etc.
        #
        # In practice Apache won't exit until the current request's KeepAlive
        # timeout is reached, so the Apache hangs around for the configured
        # amount of time before exiting.  Sinced we know that the request
        # is done and we've verified that logging as happend (above), we'll
        # just call CORE::exit(0) which works immediately.
        CORE::exit(0);
    }

    return OK;
}

sub pid_info {
    my $pid = shift;

    open( F, "/proc/$pid/stat" ) or next;
    $_ = <F>;
    close(F);
    my @f = split;
    return \@f;
}

sub child_info {
    my $ppid = shift;
    opendir( D, "/proc" ) or return undef;
    my @pids = grep { /^\d+$/ } readdir(D);
    closedir(D);

    my %ret;
    foreach my $p (@pids) {
        next if ( defined $known_parent{$p}
            && $known_parent{$p} != $ppid );
        my $ary       = pid_info($p);
        my $this_ppid = $ary->[3];
        $known_parent{$p} = $this_ppid;
        next unless $this_ppid == $ppid;
        $ret{$p} = $ary;
    }
    return \%ret;
}

1;
