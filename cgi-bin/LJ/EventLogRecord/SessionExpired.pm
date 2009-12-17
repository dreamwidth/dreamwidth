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

# session_expired
#         userid
#         sessionid

package LJ::EventLogRecord::SessionExpired;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $sess) = @_;

    croak "Must pass an LJ::Session"
        unless UNIVERSAL::isa($sess, 'LJ::Session');

    return $class->SUPER::new(
                              userid => $sess->owner->userid,
                              id     => $sess->id,
                              );
}

sub event_type { 'session_expired' }

1;
