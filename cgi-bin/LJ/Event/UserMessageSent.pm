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

package LJ::Event::UserMessageSent;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';
use LJ::Message;

sub new {
    my ($class, $u, $msgid, $other_u) = @_;
    foreach ($u, $other_u) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $msgid, $other_u->{userid});
}

sub arg_list {
    return ( "Message id", "Recipient userid" );
}

# TODO Should this return 1?
sub is_common { 1 }

sub load_message {
    my ($self) = @_;

    my $msg = LJ::Message->load({msgid => $self->arg1, journalid => $self->u->{userid}, otherid => $self->arg2});
    return $msg;
}

sub as_html {
    my $self = shift;

    my $msg = $self->load_message;
    my $sender_u = LJ::want_user($msg->journalid);
    my $pichtml = display_pic($msg, $sender_u);
    my $subject = $msg->subject;
    my $other_u = $msg->other_u;

    my $ret;
    $ret .= "<div class='pkg'><div style='width: 60px; float: left;'>";
    $ret .= $pichtml . "</div><div>";
    $ret .= $subject;
    $ret .= "<br />sent to " . $other_u->ljuser_display . "</div>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;

    my $other_u = $self->load_message->other_u;
    return sprintf("message sent to %s.",
                   $other_u->{user});
}

sub subscription_as_html {''}

sub content {
    my $self = shift;

    my $msg = $self->load_message;

    my $body = $msg->body;
    $body = LJ::html_newlines($body);

    return $body;
}

sub content_summary {
    my $msg = $_[0]->load_message;
    my $body = $msg->body;
    my $body_summary = LJ::html_trim( $body, 300 );

    my $ret = LJ::html_newlines( $body_summary );
    $ret .= "..." if $body ne $body_summary;
    $ret .= $_[0]->as_html_actions;
    return $ret;
}

# override parent class subscriptions method to always return
# a subscription object for the user
sub raw_subscriptions {
    my ( $class, $self, %args ) = @_;

    $args{ntypeid} = LJ::NotificationMethod::Inbox->ntypeid; # Inbox
    $args{skip_parent} = 1;

    return $class->_raw_always_subscribed( $self, %args );
}

sub get_subscriptions {
    my ($self, $u, $subid) = @_;

    unless ($subid) {
        my $row = { userid  => $u->{userid},
                    ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
                  };

        return LJ::Subscription->new_from_row($row);
    }

}

# Have notifications for this event show up as read
sub mark_read {
    my $self = shift;
    return 1;
}

sub display_pic {
    my ($msg, $u) = @_;

    my $pic;
    if ( defined $msg->userpic ) {
        $pic = LJ::Userpic->new_from_keyword($u, $msg->userpic);
    } else {
        $pic = $u->userpic;
    }

    # Get the image URL and the alternative text. Don't set
    # alternative text if there isn't any userpic.
    my ( $userpic_src, $userpic_alt );
    if ( defined $pic ) {
        $userpic_src = $pic->url;
        $userpic_alt = LJ::ehtml( $pic->alttext( $msg->userpic ) );
    } else {
        $userpic_src = "$LJ::IMGPREFIX/nouserpic.png";
        $userpic_alt = "";
    }

    my $ret;
    $ret .= '<img src="' . $userpic_src . '" alt="' .  $userpic_alt . '" width="50" align="top" />';

    return $ret;
}

# return detailed data for XMLRPC::getinbox
sub raw_info {
    my ($self, $target) = @_;

    my $res = $self->SUPER::raw_info;

    my $msg = $self->load_message;
    my $sender_u = LJ::want_user($msg->journalid);

    my $pic;
    if ( defined  $msg->userpic ) {
        $pic = LJ::Userpic->new_from_keyword($sender_u, $msg->userpic);
    } else {
        $pic = $sender_u->userpic;
    }

    $res->{to} = $msg->other_u->user;
    $res->{picture} = $pic->url if $pic;
    $res->{subject} = $msg->subject;
    $res->{body} = $msg->body;

    return $res;
}

1;
