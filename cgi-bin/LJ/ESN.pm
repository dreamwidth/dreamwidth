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

package LJ::ESN;
use strict;
use Log::Log4perl;
use DW::Stats;
use DW::Task::ESN::ProcessSub;
use LJ::Event;
use LJ::Subscription;

our $MAX_FILTER_SET = 5_000;
our $CURRENT_TRACE;

# Make DW::Tasks for matching subs.
sub tasks_of_unique_matching_subs {
    return map { DW::Task::ESN::ProcessSub->new(@$_) } unique_matching_subs(@_);
}

sub unique_matching_subs {
    my ( $class, $evt, @subs ) = @_;
    my %has_done = ();
    my @subjobs;

    my $log    = Log::Log4perl->get_logger(__PACKAGE__);
    my $params = $evt->raw_params;
    my $trace  = join( ':', @$params );

    if ( $ENV{DEBUG} ) {
        warn "jobs of unique subs (@subs) matching event (@$params)\n";
    }

    my %related = map { $_ => 1 } $evt->related_events;

    # Stash trace in a package global so matches_filter implementations
    # can include it in their own debug logging without API changes.
    local $LJ::ESN::CURRENT_TRACE = $trace;

    foreach my $s (@subs) {
        my $matched;
        if ( $related{ $s->etypeid } ) {
            $matched = bless( $evt, $s->event_class )->matches_filter($s);
        }
        else {
            $matched = $evt->matches_filter($s);
        }

        unless ($matched) {
            my $owner = $s->owner;
            $log->debug(
                sprintf(
                    '[esn %s] filter_reject user=%s(%d) sub=%d etypeid=%d',
                    $trace, $owner ? $owner->user : '?',
                    $s->userid, $s->id || 0,
                    $s->etypeid
                )
            );
            DW::Stats::increment( 'dw.esn.filter', 1,
                [ "result:rejected", "etypeid:" . $s->etypeid ] );
            next;
        }

        next if $has_done{ $s->unique }++;
        push @subjobs, [ $s->userid + 0, $s->id + 0, $params ];
    }
    return @subjobs;
}

1;

