package LJ::Event::InvitedFriendJoins;
use strict;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $friendu) = @_;
    foreach ($u, $friendu) {
        croak 'Not an LJ::User' unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $friendu->{userid});
}

sub is_common { 0 }

sub as_email_subject {
    my ($self, $u) = @_;
    return sprintf "%s created a journal!", $self->friend->user;
}

sub as_email_string {
    my ($self, $u) = @_;
    return '' unless $u && $self->friend;

    my $username = $u->user;
    my $newuser = $self->friend->user;
    my $newuser_url = $self->friend->journal_base;
    my $newuser_profile = $self->friend->profile_url;

    my $email = qq {Hi $username,

Your friend $newuser has created a journal on $LJ::SITENAMESHORT!

You can:
  - Add $newuser to your Friends list
    $LJ::SITEROOT/friends/add.bml?user=$newuser
  - Read $newuser\'s journal
    $newuser_url
  - View $newuser\'s profile
    $newuser_profile
  - Invite another friend
    $LJ::SITEROOT/friends/invite.bml
};

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;
    return '' unless $u && $self->friend;

    my $username = $u->ljuser_display;
    my $newuser = $self->friend->ljuser_display;
    my $newusername = $self->friend->user;
    my $newuser_url = $self->friend->journal_base;
    my $newuser_profile = $self->friend->profile_url;

    my $email = qq {Hi $username,

Your friend $newuser has created a journal on $LJ::SITENAMESHORT!

You can:<ul>};

    $email .= "<li><a href=\"$LJ::SITEROOT/friends/add.bml?user=$newusername\">Add $newusername to your Friends list</a></li>";
    $email .= "<li><a href=\"$newuser_url\">Read $newusername\'s journal</a></li>";
    $email .= "<li><a href=\"$newuser_profile\">View $newusername\'s profile</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/friends/invite.bml\">Invite another friend</a></li>";
    $email .= "</ul>";

    return $email;
}

sub as_html {
    my $self = shift;

    return 'A friend you invited has created a journal.'
        unless $self->friend;

    return sprintf "A friend you invited has created the journal %s", $self->friend->ljuser_display;
}

sub as_html_actions {
    my ($self) = @_;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $self->friend->journal_base . "'>View Journal</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;

    return 'A friend you invited has created a journal.'
        unless $self->friend;

    return sprintf "A friend you invited has created the journal %s", $self->friend->user;
}

sub as_sms {
    my $self = shift;
    return $self->as_string;
}

sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return "Someone I invited creates a new journal";
}

sub content {
    my ($self, $target) = @_;

    return $self->as_html_actions;
}

1;
