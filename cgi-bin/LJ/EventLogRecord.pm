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

# This is a class that represents any event that happened on LJ
package LJ::EventLogRecord;

use strict;
use Carp qw(croak);
use TheSchwartz;

use LJ::ModuleLoader;
LJ::ModuleLoader->autouse_subclasses('LJ::EventLogRecord');

sub schwartz_capabilities {
    return (
            "LJ::Worker::EventLogRecord",
            );
}

# Class method
# takes a list of key/value pairs
sub new {
    my ($class, %args) = @_;

    my $self = {
        params => \%args,
    };

    bless $self, $class;
    return $self;
}

# Instance method
# returns a hashref of the key/value pairs of this event
sub params {
    my $self = shift;
    my $params = $self->{params};
    return $params || {};
}

# Instance method
# creates a job to insert into the schwartz to process this firing
sub fire_job {
    my $self = shift;
    return unless LJ::is_enabled('eventlogrecord');

    my $params = $self->params;
    $params->{_event_type} = $self->event_type;
    $params->{_event_class} = $self->event_class;
    return TheSchwartz::Job->new_from_array("LJ::Worker::EventLogRecord",
                                            [ %$params ]);
}

# Instance method
# inserts a job into the schwartz to process this event
sub fire {
    my $self = shift;
    return unless LJ::is_enabled('eventlogrecord');

    my $sclient = LJ::theschwartz()
        or die "Could not get TheSchwartz client";

    $sclient->insert_jobs($self->fire_job);
}

sub event_class {
    my $self = shift;
    return ref $self;
}

# Override in subclasses
# returns what type of event this is
sub event_type {
    die "event_type called on EventLogRecord base class";
}

#############
## Schwartz worker methods
#############

package LJ::Worker::EventLogRecord;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;

    my @arglist = @$a;
    my %params = @arglist;

    my $evt_class = delete $params{_event_class} or die "No event_class specified";

    my $evt = LJ::EventLogRecord::new($evt_class, %params);

    $job->completed;
}

sub grab_for { 60 * 10 } # 10 minutes

1;
