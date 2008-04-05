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

sub is_common { 1 }

sub as_email_subject {
    my ($self, $u) = @_;

    my $other_u = $self->load_message->other_u;

    return sprintf "%s sent you a message", $other_u->display_username;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $msg = $self->load_message;
    my $other_u = $msg->other_u;
    my $user = $u->user;
    my $sender = $other_u->user;
    my $subject = $msg->subject;

    my $email = qq {Hi $user,

$sender sent you a message on $LJ::SITENAMESHORT: $subject.

Go to $LJ::SITEROOT/inbox/ to view your new messages.

};
    $email .= "Or you can:\n";
    $email .= "  - View ${sender}'s profile\n    ". $other_u->profile_url ."\n";
    $email .= "  - View ${sender}'s journal\n    ". $other_u->journal_base ."\n";
    $email .= "  - Add ${sender} as a friend\n    $LJ::SITEROOT/friends/add.bml?user=$sender\n"
        unless $u->is_friend($other_u);

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $user = $u->ljuser_display;
    my $other_u = $self->load_message->other_u;
    my $sender = $other_u->ljuser_display;
    my $username = $other_u->user;
    my $subject = $self->load_message->subject;

    my $email = qq {Hi $user,

$sender sent you a message on $LJ::SITENAMESHORT: $subject.

Go to <a href="$LJ::SITEROOT/inbox/">your Inbox</a> to view your new messages.

};
    $email .= "Or you can:\n";
    $email .= "  - <a href='". $other_u->profile_url ."'>View ${username}'s profile</a>\n";
    $email .= "  - <a href='". $other_u->journal_base ."'>View ${username}'s journal</a>\n";
    $email .= "  - <a href='$LJ::SITEROOT/friends/add.bml?user=$username'>Add $username as friend</a>\n"
        unless $u->is_friend($other_u);

    return $email;
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

    my $ret = "<div class='actions'>";
    $ret .= " <a href='$LJ::SITEROOT/inbox/compose.bml?mode=reply&msgid=$msgid'>Reply</a>";
    $ret .= " | <a href='$LJ::SITEROOT/friends/add.bml?user=". $msg->other_u->user ."'>Add as friend</a>"
        unless $u->is_friend($msg->other_u);
    $ret .= " | <a href='$LJ::SITEROOT/inbox/markspam.bml?msgid=". $msg->msgid ."'>Mark as Spam</a>";
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

sub as_sms {
    my $self = shift;

    my $subject = $self->load_message->subject;
    my $other_u = $self->load_message->other_u;
    return sprintf("You've received a new message \"%s\" from %s",
                   $subject, $other_u->user);
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal or croak "No user";

    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);

    my $user = $journal_is_owner ? "me" : $journal->ljuser_display;
    return "Someone sends $user a message";
}

sub content {
    my $self = shift;

    my $msg = $self->load_message;

    my $body = $msg->body;
    $body = LJ::html_newlines($body);

    return $body . $self->as_html_actions;
}

# override parent class sbuscriptions method to always return
# a subscription object for the user
sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @subs;
    my $u = $self->u;
    return unless ( $cid == $u->clusterid );

    my $row = { userid  => $self->u->{userid},
                ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
              };

    push @subs, LJ::Subscription->new_from_row($row);

    push @subs, eval { $self->SUPER::subscriptions(cluster => $cid,
                                                   limit   => $limit) };

    return @subs;
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
    if ($msg->userpic) {
        $pic = LJ::Userpic->new_from_keyword($u, $msg->userpic);
    } else {
        $pic = $u->userpic;
    }

    my $ret;
    $ret .= '<img src="';
    $ret .= $pic ? $pic->url : "$LJ::STATPREFIX/horizon/nouserpic.png";
    $ret .= '" width="50" align="top" />';

    return $ret;
}

# Event is always subscribed to
sub always_checked { 1 }

1;
