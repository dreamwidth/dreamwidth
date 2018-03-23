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

package LJ::Event::UserMessageRecvd;
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
    return ( "Message id", "Sender userid" );
}

sub is_common { 1 }

sub as_email_subject {
    my ($self, $u) = @_;

    my $other_u = $self->load_message->other_u;

    return LJ::Lang::get_default_text( 'esn.email.pm.subject',
        {
            sender => $self->load_message->other_u->display_username,
        });
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $msg         = $self->load_message;
    my $replyurl    = "$LJ::SITEROOT/inbox/compose?mode=reply&msgid=" . $msg->msgid;
    my $other_u     = $msg->other_u;
    my $sender      = $other_u->user;
    my $inbox       = "$LJ::SITEROOT/inbox/";
    $inbox = "<a href=\"$inbox\">" . LJ::Lang::get_default_text( 'esn.your_inbox' ) . "</a>"
        if $is_html;

    my $vars = {
        user            => $is_html ? ($u->ljuser_display) : ($u->user),
        subject         => $is_html ? $msg->subject : $msg->subject_raw,
        body            => $is_html ? $msg->body : $msg->body_raw,
        sender          => $is_html ? ($other_u->ljuser_display) : ($other_u->user),
        postername      => $other_u->display_name,
        journal         => $other_u->display_name,
        sitenameshort   => $LJ::SITENAMESHORT,
        inbox           => $inbox,
    };

    my $body = LJ::Lang::get_default_text( 'esn.email.pm_with_body', $vars ) .
        $self->format_options($is_html, undef, $vars,
        {
            'esn.reply_to_message' => [ 1, $replyurl ],
            'esn.view_profile'     => [ 2, $other_u->profile_url ],
            'esn.read_journal'     => [ $other_u->is_identity ? 0 : 3, $other_u->journal_base ],
            'esn.add_watch'        => [ $u->watches( $other_u ) ? 0 : 4,
                                             "$LJ::SITEROOT/circle/$sender/edit?action=subscribe" ],
        }
    );

    if ($is_html) {
        $body =~ s/\n/\n<br\/>/g unless $body =~ m!<br!i;
    }

    return $body;
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, $u, 1);
}

sub load_message {
    my ($self) = @_;

    my $msg = LJ::Message->load({msgid => $self->arg1, journalid => $self->u->{userid}, otherid => $self->arg2});
    return $msg;
}

sub as_html {
    my $self = shift;

    my $msg = $self->load_message;
    my $other_u = $msg->other_u;
    my $pichtml = display_pic($msg, $other_u);
    my $subject = $msg->subject;

    if ( $other_u->is_suspended ) {
        $subject = "(Message from suspended user)";
    }

    my $ret;
    $ret .= "<div class='pkg'><div style='width: 60px; float: left;'>";
    $ret .= $pichtml . "</div><div>";
    $ret .= $subject;
    $ret .= "<br />from " . $other_u->ljuser_display . "</div>";
    $ret .= "</div>";

    return $ret;
}

sub as_html_actions {
    my $self = shift;

    my $msg = $self->load_message;
    my $msgid = $msg->msgid;
    my $u = LJ::want_user($msg->journalid);
    my $other_u = $msg->other_u;

    my $ret = "<div class='actions'>";
    if (! $other_u->is_suspended ) {
        $ret .= " <a href='$LJ::SITEROOT/inbox/compose?mode=reply&msgid=$msgid'>Reply</a>";
        $ret .= " | <a href='$LJ::SITEROOT/circle/". $msg->other_u->user ."/edit?action=subscribe'>Subscribe to ". $msg->other_u->user ."</a>"
            unless $u->watches( $msg->other_u );
        $ret .= " | <a href='$LJ::SITEROOT/inbox/markspam?msgid=". $msg->msgid ."'>Mark as Spam</a>"
            unless LJ::sysban_check( 'spamreport', $u->user );
    }
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;

    my $subject = $self->load_message->subject;
    my $other_u = $self->load_message->other_u;
    my $ret = sprintf("You've received a new message \"%s\" from %s. %s",
                   $subject, $other_u->{user}, "$LJ::SITEROOT/inbox/");
    return $ret;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal or croak "No user";

    # "Someone sends $user a message"
    # "Someone sends me a message"
    return $journal->equals( $subscr->owner ) ?
        BML::ml('event.user_message_recvd.me') :
        BML::ml('event.user_message_recvd.user', { user => $journal->ljuser_display } );
}

sub content {
    my $self = shift;

    my $msg = $self->load_message;

    my $body = $msg->body;
    my $other_u = $msg->other_u;

    if ( $other_u->is_suspended ) {
        $body = "(Message from suspended user)";
    }
    $body = LJ::html_newlines($body);
    $body = "<div class='actions_top'>" . $self->as_html_actions . "</div>" . $body
        if LJ::has_too_many( $body, linebreaks => 10, characters => 2000 );

    return $body . $self->as_html_actions;
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

    return $self->SUPER::get_subscriptions($u, $subid);
}

sub display_pic {
    my ($msg, $u) = @_;

    my $pic;

    # Get the userpic object
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

# Event is always subscribed to
sub always_checked { 1 }

# return detailed data for XMLRPC::getinbox
sub raw_info {
    my ($self, $target) = @_;

    my $res = $self->SUPER::raw_info;

    my $msg = $self->load_message;

    my $pic;
    if ( defined $msg->userpic ) {
        $pic = LJ::Userpic->new_from_keyword($msg->other_u, $msg->userpic);
    } else {
        $pic = $msg->other_u->userpic;
    }

    $res->{from} = $msg->other_u->user;
    $res->{picture} = $pic->url if $pic;
    $res->{subject} = $msg->subject;
    $res->{body} = $msg->body;
    $res->{msgid} = $msg->msgid;
    $res->{parent} = $msg->parent_msgid if $msg->parent_msgid;

    return $res;
}

1;
