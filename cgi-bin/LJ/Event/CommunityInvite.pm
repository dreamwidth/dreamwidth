package LJ::Event::CommunityInvite;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu, $commu) = @_;
    foreach ($u, $fromu, $commu) {
        LJ::errobj('Event::CommunityInvite', u => $_)->throw unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $fromu->{userid}, $commu->{userid});
}

sub is_common { 0 }

sub as_email_subject {
    my $self = shift;
    return sprintf "You've been invited to join %s", $self->comm->user;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->user;
    my $maintainer = $self->inviter->user;
    my $community = $self->comm->user;
    my $community_url = $self->comm->journal_base;
    my $community_profile = $self->comm->profile_url;

    my $email = qq{Hi $username,

$maintainer has invited you to join the community $community!

You can:
  - Manage your invitations
    $LJ::SITEROOT/manage/invites.bml
  - Read the latest entries in $community
    $community_url
  - View $community\'s profile
    $community_profile};

    $email .= "
  - Add $community to your Friends list
    $LJ::SITEROOT/friends/add.bml?user=$community"
       unless LJ::is_friend($u, $self->comm);

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $maintainer = $self->inviter->ljuser_display;
    my $community = $self->comm->ljuser_display;
    my $communityname = $self->comm->user;
    my $community_url = $self->comm->journal_base;
    my $community_profile = $self->comm->profile_url;

    my $email = qq{Hi $username,

$maintainer has invited you to join the community $community!

You can:<ul>};

    $email .= "<li><a href=\"$LJ::SITEROOT/manage/invites.bml\">Manage your invitations</a></li>";
    $email .= "<li><a href=\"$community_url\">Read the latest entries in $communityname</a></li>";
    $email .= "<li><a href=\"$community_profile\">View $communityname\'s profile</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/friends/add.bml?user=$communityname\">Add $communityname to your Friends list</a></li>"
        unless LJ::is_friend($u, $self->comm);

    $email .= "</ul>";

    return $email;
}

sub inviter {
    my $self = shift;
    my $u = LJ::load_userid($self->arg1);
    return $u;
}

sub comm {
    my $self = shift;
    my $u = LJ::load_userid($self->arg2);
    return $u;
}

sub as_html {
    my $self = shift;
    return sprintf("The user %s has <a href=\"$LJ::SITEROOT/manage/invites.bml\">invited you to join</a> the community %s.",
                   $self->inviter->ljuser_display,
                   $self->comm->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $self->comm->profile_url . "'>View Profile</a>";
    $ret .= " <a href='$LJ::SITEROOT/manage/invites.bml'>Join Community</a>";
    $ret .= "</div>";

    return $ret;
}

sub content {
    my ($self, $target) = @_;
    return $self->as_html_actions;
}

sub as_string {
    my $self = shift;
    return sprintf("The user %s has invited you to join the community %s.",
                   $self->inviter->display_username,
                   $self->comm->display_username);
}

sub as_sms {
    my $self = shift;

    return sprintf("%s sent you an invitation to join the community %s. Visit the invitation page to accept",
                   $self->inviter->display_username,
                   $self->comm->display_username);
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return "I receive an invitation to join a community";
}

package LJ::Error::Event::CommunityInvite;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityInvite passed bogus u object: $self->{u}";
}

1;
