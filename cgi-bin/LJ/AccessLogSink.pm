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

package LJ::AccessLogSink;
use strict;
use warnings;
use LJ::ModuleCheck;

sub new {
    die "this is a base class\n";
}

sub log {
    my ($self, $rec) = @_;
    die "this is a base class\n";
}

my $need_rebuild = 1;
my @sinks = ();

sub forget_sink_objs {
    $need_rebuild = 1;
    @sinks = ();
}

sub extra_log_sinks {
    _build_sink_objs() if $need_rebuild;
    return @sinks;
}

sub _build_sink_objs {
    return unless $need_rebuild;
    $need_rebuild = 0;
    @sinks = ();
    foreach my $ci (@LJ::EXTRA_ACCESS_LOG_SINKS) {
        if (ref $ci eq "ARRAY") {
            # convert from [$class, @ctor_args] arrayref
            my @args = @$ci;
            my $class = shift @args;
            $class = "LJ::AccessLogSink::$class" unless $class =~ /::/;
            unless (LJ::ModuleCheck->have($class)) {
                warn "Can't load module: $class\n";
                next;
            }
            push @sinks, $class->new(@args);
        } else {
            # already an object in etc/config.pl (old style)
            push @sinks, $ci;
        }
    }
}

1;
