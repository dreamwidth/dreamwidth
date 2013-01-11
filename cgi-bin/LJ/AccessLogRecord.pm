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

package LJ::AccessLogRecord;
use strict;

sub new {
    my ($class, $apache_r) = @_;
    my $apache_rl = $apache_r->last;

    my $now = time();
    my @now = gmtime($now);

    my $remote = eval { LJ::load_user($apache_rl->notes('ljuser')) };
    my $remotecaps = $remote ? $remote->{caps} : undef;
    my $remoteid   = $remote ? $remote->{userid} : 0;
    my $ju = eval { LJ::load_userid($apache_rl->notes('journalid')) };
    my $ctype = $apache_rl->content_type;
    $ctype =~ s/;.*//;  # strip charset

    my $self = bless {
        '_now' => $now,
        '_r'   => $apache_r,
        'whn' => sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, @now[3, 2, 1, 0]),
        'whnunix' => $now,
        'server' => $LJ::SERVER_NAME,
        'addr' => $apache_r->connection->remote_ip,
        'ljuser' => $apache_rl->notes('ljuser'),
        'remotecaps' => $remotecaps,
        'remoteid'   => $remoteid,
        'journalid' => $apache_rl->notes('journalid'),
        'journaltype' => ($ju ? $ju->{journaltype} : ""),
        'journalcaps' => ($ju ? $ju->{caps} : undef),
        'codepath' => $apache_rl->notes('codepath'),
        'anonsess' => $apache_rl->notes('anonsess'),
        'langpref' => $apache_rl->notes('langpref'),
        'clientver' => $apache_rl->notes('clientver'),
        'uniq' => $apache_r->notes('uniq'),
        'method' => $apache_r->method,
        'uri' => $apache_r->uri,
        'args' => scalar $apache_r->args,
        'status' => $apache_rl->status,
        'ctype' => $ctype,
        'bytes' => $apache_rl->bytes_sent,
        'browser' => $apache_r->header_in("User-Agent"),
        'secs' => $now - $apache_r->request_time(),
        'ref' => $apache_r->header_in("Referer"),
    }, $class;
    $self->populate_gtop_info($apache_r);
    return $self;
}

sub keys {
    my $self = shift;
    return grep { $_ !~ /^_/ } keys %$self;
}

sub populate_gtop_info {
    my ($self, $apache_r) = @_;

    # If the configuration says to log statistics and GTop is available, then
    # add those data to the log
    # The GTop object is only created once per child:
    #   Benchmark: timing 10000 iterations of Cached GTop, New Every Time...
    #   Cached GTop: 2.06161 wallclock secs ( 1.06 usr +  0.97 sys =  2.03 CPU) @ 4926.11/s (n=10000)
    #   New Every Time: 2.17439 wallclock secs ( 1.18 usr +  0.94 sys =  2.12 CPU) @ 4716.98/s (n=10000)
    my $GTop = LJ::gtop() or return;

    my $startcpu = $apache_r->pnotes( 'gtop_cpu' ) or return;
    my $endcpu = $GTop->cpu                 or return;
    my $startmem = $apache_r->pnotes( 'gtop_mem' ) or return;
    my $endmem = $GTop->proc_mem( $$ )      or return;
    my $cpufreq = $endcpu->frequency        or return;

    # Map the GTop values into the corresponding fields in a slice
    @$self{qw{pid cpu_user cpu_sys cpu_total mem_vsize
              mem_share mem_rss mem_unshared}} =
        (
         $$,
         ($endcpu->user - $startcpu->user) / $cpufreq,
         ($endcpu->sys - $startcpu->sys) / $cpufreq,
         ($endcpu->total - $startcpu->total) / $cpufreq,
         $endmem->vsize - $startmem->vsize,
         $endmem->share - $startmem->share,
         $endmem->rss - $startmem->rss,
         $endmem->size - $endmem->share,
         );
}

sub ip { $_[0]{addr} }
sub r  { $_[0]{_r} }

sub table {
    my ($self, $prefix) = @_;
    my @now = gmtime($self->{_now});
    return ($prefix || "access") .
        sprintf("%04d%02d%02d%02d",
                $now[5]+1900,
                $now[4]+1,
                $now[3],
                $now[2]);
}

1;
