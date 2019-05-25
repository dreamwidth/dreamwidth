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

package LJ::NotificationMethod::DebugLog;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';

use LJ::Web;

sub can_digest { 1 }

# takes a $subscr and $orig_class
sub new {
    my $class = shift;

    croak "no args passed"
        unless @_;

    my $subscr = shift
        or croak "No subscription passed";

    my $orig_class = shift
        or croak "No original class passed";

    my $self = {
        subscr     => $subscr,
        orig_class => $orig_class,
    };

    return bless $self, $class;
}

sub new_from_subscription {
    my $class      = shift;
    my $subscr     = shift;
    my $orig_class = shift;

    return $class->new( $subscr, $orig_class );
}

sub title { 'DebugLog' }

# send emails for events passed in
sub notify {
    my $self = shift;
    croak "'notify' is an object method"
        unless ref $self eq __PACKAGE__;

    my @events = @_
        or croak "'notify' requires one or more events";

    my $db = LJ::get_dbh("slow")
        or die "Could not get db";

    my $orig_nclass  = $self->{orig_class};
    my $orig_ntypeid = $orig_nclass->ntypeid;

    my $debug_headers = $self->{_debug_headers} || {};

    foreach my $ev (@events) {
        my %logrow = (
            userid      => $self->subscr->owner->userid,
            subid       => $self->subscr->id,
            ntfytime    => time(),
            origntypeid => $orig_ntypeid,
            etypeid     => $ev->etypeid,
            ejournalid  => $ev->event_journal->userid,
            earg1       => $ev->arg1,
            earg2       => $ev->arg2,
            schjobid    => $debug_headers->{'X-ESN_Debug-sch_jobid'},
        );

        my $cols = join( ',', keys %logrow );
        my @vals = values %logrow;
        my $bind = join( ',', map { '?' } @vals );

        $db->do( "INSERT INTO debug_notifymethod ($cols) VALUES ($bind)", undef, @vals );

        die $db->errstr if $db->err;
    }

    return 1;
}

sub configured {
    my $class = shift;
    return 1;
}

sub configured_for_user {
    my $class = shift;
    my $u     = shift;
    return 1;
}

sub subscr { $_[0]->{subscr} }

1;
