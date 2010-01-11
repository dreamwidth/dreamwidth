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

package LJ::Event::UserNewEntry;

#
# UserNewEntry Event: Fired when a 'poster' posts 'entry' in 'journal'
#

use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use LJ::Entry;
use base 'LJ::Event';

############################################################################
# constructor & property overrides
#

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->poster, $entry->journalid, $entry->ditemid);
}

sub is_common { 0 }

############################################################################
# canonical accessors into the meaning of this event's arguments
#  * poster:  user object who posted
#  * journal: journal u object where entry was posted
#  * entry:   entry object which was posted (from journal, ditemid)
#

# user who posted the entry
sub poster {
    my $self = shift;
    return $self->u;
}

sub posterid {
    my $self = shift;
    return $self->u->{userid};
}

# journal entry was posted in
sub journal {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub journalid {
    my $self = shift;
    return $self->arg1+0;
}

# entry which was posted
sub entry {
    my $self = shift;
    return LJ::Entry->new($self->journal, ditemid => $self->ditemid);
}

sub ditemid {
    my $self = shift;
    return $self->arg2;
}

############################################################################
# subscription matching logic
#

sub matches_filter {
    my ($self, $subscr) = @_;

    # does the entry actually exist?
    return 0 unless $self->journalid && $self->ditemid; # TODO: throw error?

    # construct the entry so we can determine visibility
    my $entry = $self->entry;
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # journalid of 0 means 'all friends', so if the poster is
    # watched by the subscription owner, then they match
    return 1 if ! $subscr->journalid && $subscr->owner->watches( $self->poster );

    # otherwise we have a journalid, see if it's the specific
    # journal that the subscription is watching
    return LJ::u_equals($subscr->journal, $self->poster);
}


############################################################################
# methods for rendering ->as_*
#

sub as_string {
    my $self = shift;
    my $entry = $self->entry;
    my $about = $entry->subject_text ? " titled '" . $entry->subject_text . "'" : '';
    return sprintf("User '%s' made a new entry $about at: " . $self->entry->url,
                   $self->poster->{name});
}

sub as_html {
    my $self = shift;

    my $entry = $self->entry;
    return "(Invalid entry)" unless $entry && $entry->valid;
    my $url = $entry->url;

    my $ju = LJ::ljuser($self->journal);
    my $pu = LJ::ljuser($self->poster);

    return "User $pu has posted a new <a href=\"$url\">entry</a> in $ju.";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    # journal is the 'watched journal' of the subscription
    #  * 0 means the subscription is for posts by any friend
    my $journal = $subscr->journal;

    # non-zero journal means the subscription refers to
    # posts made by a specific user

    return $journal ?
        BML::ml('event.user_new_entry.user', { user => $journal->ljuser_display } ) : # $journaluser posts a new entry anywhere.
        BML::ml('event.user_new_entry.any'); # "Any of my friends posts a new entry anywhere."
}

1;
