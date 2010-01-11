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

package LJ::Event::UserNewComment;
use strict;
use Scalar::Util qw(blessed);
use LJ::Comment;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $comment) = @_;
    croak 'Not an LJ::Comment' unless blessed $comment && $comment->isa("LJ::Comment");
    return $class->SUPER::new($comment->poster,
                              $comment->journal->{userid}, $comment->jtalkid);
}

sub is_common { 0 }

# when was this comment left?
sub eventtime_unix {
    my $self = shift;
    my $cmt = $self->comment;
    return $cmt ? $cmt->unixtime : $self->SUPER::eventtime_unix;
}

sub comment {
    my $self = shift;
    return LJ::Comment->new($self->journal, jtalkid => $self->arg1);
}

1;
