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

        # If the sub requires a capability the user no longer has (e.g. paid
        # expired but thread-tracking sub remains) AND the user has been idle
        # for over a year, deactivate the sub so it stops generating wasted
        # ProcessSub jobs. We only do this for idle users — active users who
        # just lost paid time should keep their subs (they still show in the UI
        # even if notifications don't fire) so they don't have to re-find them.
        unless ( $s->available_for_user ) {
            my $owner     = $s->owner;
            my $idle_days = $owner ? int( ( time() - $owner->get_timeactive ) / 86400 ) : 0;
            if ( $idle_days > ( $LJ::ESN_INACTIVE_DAYS // 365 ) ) {
                $log->debug(
                    sprintf(
'[esn %s] deactivating unavailable sub user=%s(%d) sub=%d etypeid=%d idle_days=%d',
                        $trace, $owner->user, $owner->id, $s->id || 0,
                        $s->etypeid, $idle_days
                    )
                );
                DW::Stats::increment( 'dw.esn.filter', 1,
                    [ "result:deactivated", "etypeid:" . $s->etypeid ] );
                $s->_deactivate;
            }
            next;
        }

        my $matched;
        if ( $related{ $s->etypeid } ) {
            $matched = bless( $evt, $s->event_class )->matches_filter($s);
        }
        else {
            $matched = $evt->matches_filter($s);
        }

        unless ($matched) {
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

