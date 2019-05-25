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

package LJ::Event::PollVote;
use strict;
use base 'LJ::Event';
use LJ::Poll;
use Carp qw(croak);

# we need to specify 'owner' here, because subscriptions are tied
# to the *poster*, not the journal, and we want to fire to the right
# person. we could divine this information from the poll itself,
# but it quickly becomes complicated.
sub new {
    my ( $class, $owner, $voter, $poll ) = @_;
    croak "No poll owner" unless $owner;
    croak "No poll!"      unless $poll;
    croak "No voter!"     unless $voter && LJ::isu($voter);

    return $class->SUPER::new( $owner, $voter->userid, $poll->id );
}

sub arg_list {
    return ( "Voter userid", "Poll id" );
}

sub matches_filter {
    my ( $self, $subscr ) = @_;

    return 0 unless $subscr->available_for_user;

    # don't notify voters of their own answers
    return $self->voter->equals( $self->event_journal ) ? 0 : 1;
}

## some utility methods
sub voter {
    my $self = shift;
    return LJ::load_userid( $self->arg1 );
}

sub poll {
    my $self = shift;
    return LJ::Poll->new( $self->arg2 );
}

sub entry {
    my $self = shift;
    return $self->poll->entry;
}

sub pollname {
    my $self = shift;
    my $poll = $self->poll;
    my $name = $poll->name;

    return sprintf( "Poll #%d", $poll->id ) unless $name;

    LJ::Poll->clean_poll( \$name );
    return sprintf( "Poll #%d (\"%s\")", $poll->id, $name );
}

## notification methods

sub as_string {
    my $self = shift;

    my $voter =
        ( $self->poll->isanon eq "yes" ) ? "Anonymous user" : $self->voter->display_username;
    return sprintf( "%s has voted in %s at %s", $voter, $self->pollname, $self->entry->url );
}

sub as_html {
    my $self  = shift;
    my $voter = ( $self->poll->isanon eq "yes" ) ? "Anonymous user" : $self->voter->ljuser_display;
    my $poll  = $self->poll;

    return sprintf( "%s has voted in a deleted poll", $voter )
        unless $poll && $poll->valid;

    my $entry = $self->entry;
    return sprintf( "%s has voted <a href='%s'>in %s</a>", $voter, $entry->url, $self->pollname );
}

sub as_html_actions {
    my $self = shift;

    my $entry_url = $self->entry->url;
    my $poll_url  = $self->poll->url;
    my $ret       = "<div class='actions'>";
    $ret .= " <a href='$poll_url'>View poll status</a> |";
    $ret .= " <a href='$entry_url'>Discuss results</a>";
    $ret .= "</div>";

    return $ret;
}

my @_ml_strings = (
    'esn.poll_vote.email_text',    #Hi [[user]],
                                   #
                                   #[[voter]] has replied to [[pollname]].
                                   #
                                   #You can:
                                   #
    'esn.poll_vote.subject2',      #Someone replied to poll #[[number]]: [[topic]].
    'esn.view_poll_status',        #[[openlink]]View the poll's status[[closelink]]
    'esn.discuss_poll'             #[[openlink]]Discuss the poll[[closelink]]
);

sub as_email_subject {
    my $self = shift;
    my $u    = shift;
    if ( $self->poll->name ) {
        return LJ::Lang::get_default_text( 'esn.poll_vote.subject2',
            { number => $self->poll->id, topic => $self->poll->name } );
    }
    else {
        return LJ::Lang::get_default_text( 'esn.poll_vote.subject2.notopic',
            { number => $self->poll->id } );
    }
}

sub _as_email {
    my ( $self, $u, $is_html ) = @_;
    my $voter = $is_html ? ( $self->voter->ljuser_display ) : ( $self->voter->display_username );

    my $vars = {
        user => $is_html ? ( $u->ljuser_display ) : ( $u->display_username ),
        voter    => ( $self->poll->isanon eq "yes" ) ? "Anonymous user" : $voter,
        pollname => $self->pollname,
    };

    # Precache text lines
    LJ::Lang::get_default_text_multi( \@_ml_strings );

    return LJ::Lang::get_default_text( 'esn.poll_vote.email_text', $vars )
        . $self->format_options(
        $is_html, undef, $vars,
        {
            'esn.view_poll_status' => [ 1, $self->poll->url ],
            'esn.discuss_poll'     => [ 2, $self->entry->url ],
        }
        );
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 0 );
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 1 );
}

sub content {
    my ( $self, $target ) = @_;

    return $self->as_html_actions;
}

sub subscription_as_html {
    my ( $class, $subscr ) = @_;

    my $pollid = $subscr->arg1;

    return $pollid ? BML::ml('event.poll_vote.id') :    # "Someone votes in poll #$pollid";
        BML::ml('event.poll_vote.me');    # "Someone votes in a poll I posted" unless $pollid;
}

# only users with the track_pollvotes cap can use this
sub available_for_user {
    my ( $class, $u, $subscr ) = @_;
    return $u->can_track_pollvotes;
}

1;
