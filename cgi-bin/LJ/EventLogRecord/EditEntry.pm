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

package LJ::EventLogRecord::EditEntry;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $e) = @_;

    croak "Must pass an LJ::Entry"
        unless UNIVERSAL::isa($e, 'LJ::Entry');

    return $class->SUPER::new(
                              journalid => $e->journalid,
                              jitemid   => $e->jitemid,
                              );
}

sub event_type { 'edit_entry' }

1;
