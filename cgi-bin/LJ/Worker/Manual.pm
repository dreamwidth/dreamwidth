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

package LJ::Worker::Manual;
use strict;
use base 'LJ::Worker';
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
use Getopt::Long;

my $interval = 5;
my $verbose  = 0;
die "Unknown options"
    unless GetOptions(
    'interval|n=i' => \$interval,
    'verbose|v'    => \$verbose
    );

my $quit_flag = 0;
$SIG{TERM} = sub {
    $quit_flag = 1;
};

# don't override this in subclasses.
sub run {
    my $class = shift;

    LJ::Worker->setup_mother();

    my $sleep = 0;
    while (1) {
        LJ::start_request();
        LJ::Worker->check_limits();
        $class->cond_debug("$class looking for work...");
        my $did_work = eval { $class->work };
        if ($@) {
            $class->error("Error working: $@");
        }
        $class->cond_debug("  did work = $did_work");
        exit 0 if $quit_flag;
        $class->on_afterwork($did_work);
        if ($did_work) {
            $sleep = 0;
            next;
        }
        $class->on_idle;

        # do some cleanup before we process another request
        LJ::end_request();

        $sleep = $interval if ++$sleep > $interval;
        sleep $sleep;
    }
}

sub verbose { $verbose }

sub work {
    print "NO WORK FUNCTION DEFINED\n";
    return 0;
}

sub on_afterwork { }
sub on_idle      { }

sub error {
    my ( $class, $msg ) = @_;
    $class->debug($msg);
}

sub debug {
    my ( $class, $msg ) = @_;
    $msg =~ s/\s+$//;
    print STDERR "$msg\n";
}

sub cond_debug {
    my $class = shift;
    return unless $verbose;
    $class->debug(@_);

}

1;
