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

package LJ::Worker::Gearman;
use strict;
use Gearman::Worker;
use base "LJ::Worker", "Exporter";
use LJ::WorkerResultStorage;

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
use Getopt::Long;
use IO::Socket::INET ();
use Carp qw(croak);

my $quit_flag = 0;
$SIG{TERM} = sub {
    $quit_flag = 1;
};

my $opt_verbose;
die "Unknown options" unless
    GetOptions("verbose|v" => \$opt_verbose);

our @EXPORT = qw(gearman_decl gearman_work gearman_set_idle_handler gearman_set_requester_id);

my $worker = Gearman::Worker->new;
my $idle_handler;
my $requester_id; # userid, who requested job, optional

sub gearman_set_requester_id { $requester_id = $_[0]; }

sub gearman_decl {
    my $name = shift;
    my ($subref, $timeout);

    if (ref $_[0] eq 'CODE') {
        $subref = shift;
    } else {
        $timeout = shift;
        $subref = shift;
    }

    $subref = wrapped_verbose($name, $subref) if $opt_verbose;

    if (defined $timeout) {
        $worker->register_function($name => $timeout => $subref);
    } else {
        $worker->register_function($name => $subref);
    }
}

# set idle handler
sub gearman_set_idle_handler {
    my $cb = shift;
    return unless ref $cb eq 'CODE';
    $idle_handler = $cb;
}

sub gearman_work {
    my %opts = @_;
    my $save_result = delete $opts{save_result} || 0;

    croak "unknown opts passed to gearman_work: " . join(', ', keys %opts)
        if keys %opts;

    if ($LJ::IS_DEV_SERVER) {
        die "DEVSERVER help: No gearmand servers listed in \@LJ::GEARMAN_SERVERS.\n"
            unless @LJ::GEARMAN_SERVERS;
        IO::Socket::INET->new(PeerAddr => $LJ::GEARMAN_SERVERS[0])
            or die "First gearmand server in \@LJ::GEARMAN_SERVERS ($LJ::GEARMAN_SERVERS[0]) isn't responding.\n";
    }

    LJ::Worker->setup_mother();

    # save the results of this worker
    my $storage;

    my $last_death_check = time();

    my $periodic_checks = sub {
        LJ::Worker->check_limits();

        # check to see if we should die
        my $now = time();
        if ($now != $last_death_check) {
            $last_death_check = $now;
            exit 0 if -e "/var/run/gearman/$$.please_die" || -e "/var/run/ljworker/$$.please_die";
        }

        $worker->job_servers(@LJ::GEARMAN_SERVERS); # TODO: don't do this everytime, only when config changes?

        exit 0 if $quit_flag;
    };

    my $start_cb = sub {
        my $handle = shift;

        LJ::start_request();
        undef $requester_id;

        # save to db that we are starting the job
        if ($save_result) {
            $storage = LJ::WorkerResultStorage->new(handle => $handle);
            $storage->init_job;
        }
    };

    my $end_work = sub {
        LJ::end_request();
        $periodic_checks->();
    };

    # create callbacks to save job status
    my $complete_cb = sub {
        $end_work->();
        my ($handle, $res) = @_;
        $res ||= '';

        if ($save_result && $storage) {
            my %row = (result   => $res,
                       status   => 'success',
                       end_time => 1);
            $row{userid} = $requester_id if defined $requester_id;
            $storage->save_status(%row);
        }
    };

    my $fail_cb = sub {
        $end_work->();
        my ($handle, $err) = @_;
        $err ||= '';

        if ($save_result && $storage) {
            my %row = (result   => $err,
                       status   => 'error',
                       end_time => 1);
            $row{userid} = $requester_id if defined $requester_id;
            $storage->save_status(%row);
        }

    };

    while (1) {
        $periodic_checks->();
        warn "waiting for work...\n" if $opt_verbose;

        # do the actual work
        eval {
            $worker->work(
                stop_if     => sub { $_[0] },
                on_complete => $complete_cb,
                on_fail     => $fail_cb,
                on_start    => $start_cb,
            );
        };
        warn $@ if $@;

        if ($idle_handler) {
            eval { 
                LJ::start_request();
                $idle_handler->();
                LJ::end_request();
            };
            warn $@ if $@;
        }
    }
}

# --------------

sub wrapped_verbose {
    my ($name, $subref) = @_;
    return sub {
        warn "  executing '$name'...\n";
        my $ans = eval { $subref->(@_) };
        if ($@) {
            warn "   -> ERR: $@\n";
            die $@; # re-throw
        } elsif (! ref $ans && $ans !~ /^[\0\x7f-\xff]/) {
            my $cleanans = $ans;
            $cleanans =~ s/[^[:print:]]+//g;
            $cleanans = substr($cleanans, 0, 1024) . "..." if length $cleanans > 1024;
            warn "   -> answer: $cleanans\n";
        }
        return $ans;
    };
}

1;
