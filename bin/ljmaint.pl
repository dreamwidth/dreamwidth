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


use strict;
BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

our ( %maint, %maintinfo, $VERBOSE );

unless ( LJ::is_enabled('ljmaint_tasks') ) {
    print "ljmaint.pl tasks disabled, exiting\n";
    exit 0;
}

my $MAINT = "$LJ::HOME/bin/maint";

load_tasks();

$VERBOSE = 1;   # 0=quiet, 1=normal, 2=verbose

if (@ARGV)
{
    ## check the correctness of the taskinfo files
    if ($ARGV[0] eq "--check") {
        foreach my $task (keys %maintinfo)
        {
            my %loaded;
            my $source = $maintinfo{$task}->{'source'};
            unless (-e "$MAINT/$source") {
                print "$task references missing file $source\n";
                next;
            }
            unless ($loaded{$source}++) {
                require "$MAINT/$source";
            }
            unless (ref $maint{$task} eq "CODE") {
                print "$task is missing code in $source\n";
            }
        }
        exit 0;
    }

    if ($ARGV[0] =~ /^-v(.?)/) {
        if ($1 eq "") { $VERBOSE = 2; }
        else { $VERBOSE = $1; }
        shift @ARGV;
    }

    my @targv;
    my $hit_colon = 0;
    my $exit_status = 0;
    foreach my $arg (@ARGV)
    {
        if ($arg eq ';') {
            $hit_colon = 1;
            $exit_status = 1 unless
                run_task(@targv);
            @targv = ();
            next;
        }
        push @targv, $arg;
    }

    if ($hit_colon) {
        # new behavior: task1 arg1 arg2 ; task2 arg arg2
        $exit_status = 1 unless
            run_task(@targv);
    } else {
        # old behavior: task1 task2 task3  (no args, ever)
        foreach my $task (@targv) {
            $exit_status = 1 unless
                run_task($task);
        }
    }
    exit($exit_status);
}
else
{
    print "Available tasks: \n";
    foreach (sort keys %maintinfo) {
        print "  $_ - $maintinfo{$_}->{'des'}\n";
    }
}

sub run_task
{
    my $task = shift;
    return unless ($task);
    my @args = @_;

    print "Running task '$task':\n\n" if ($VERBOSE >= 1);
    unless ($maintinfo{$task}) {
        print "Unknown task '$task'\n";
        return;
    }

    $LJ::LJMAINT_VERBOSE = $VERBOSE;

    require "$MAINT/$maintinfo{$task}->{'source'}";
    my $opts = $maintinfo{$task}{opts} || {};
    my $lock = undef;
    my $lockname = "mainttask-$task";
    if ($opts->{'locking'} eq "per_host") {
        $lockname .= "-$LJ::SERVER_NAME";
    }
    unless ($opts->{no_locking} ||
            ($lock = LJ::locker()->trylock($lockname))
            ) {
        print "Task '$task' already running ($DDLockClient::Error).  Quitting.\n" if $VERBOSE >= 1;
        exit 0;
    }

    eval {
        $maint{$task}->(@args);
    };
    if ( $@ ) {
        print STDERR "ERROR> task $task died: $@\n\n";
        return 0;
    }
    return 1;
}

sub load_tasks
{
    foreach my $filename (qw(taskinfo.txt taskinfo-local.txt))
    {
        my $file = "$MAINT/$filename";
        open (F, $file) or next;
        my $source;
        while (my $l = <F>) {
            next if ($l =~ /^\#/);
            if ($l =~ /^(\S+):\s*/) {
                $source = $1;
                next;
            }
            if ($l =~ /^\s*(\w+)\s*-\s*(.+?)\s*$/) {
                $maintinfo{$1}->{'des'} = $2;
                $maintinfo{$1}->{'source'} = $source;
            }
        }
        close (F);
    }
}

