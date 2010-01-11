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

# new_comment
#         jtalkid
#         ditemid
#         journal.userid
#         journal.user
#         poster.caps
#         security {public, protected, private}  (of ditemid)

package LJ::EventLogRecord::NewComment;

use strict;
use base 'LJ::EventLogRecord';
use Carp qw (croak);

sub new {
    my ($class, $c) = @_;

    croak "Must pass an LJ::Comment"
        unless UNIVERSAL::isa($c, 'LJ::Comment');

    return $class->SUPER::new(
                              'jtalkid'        => $c->jtalkid,
                              'ditemid'        => $c->entry->ditemid,
                              'journal.userid' => $c->journal->userid,
                              'journal.user'   => $c->journal->user,
                              'poster.caps'    => $c->poster ? $c->poster->caps : 0,
                              'poster.userid'  => $c->poster ? $c->poster->userid : 0,
                              'security'       => $c->entry->security,
                              );
}

sub event_type { 'new_comment' }

1;
