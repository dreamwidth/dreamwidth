package LJ::Event::Defriended;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu) = @_;
    foreach ($u, $fromu) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $fromu->{userid});
}

sub is_common { 0 }

sub as_email_subject {
    my ($self, $u) = @_;

    return sprintf "%s removed you from their Friends list", $self->friend->display_username;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $user = $u->user;
    my $poster = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $journal_profile = $self->friend->profile_url;

    my $email = qq {Hi $user,

$poster has removed you from their Friends list.

You can:};

    $email .= "
  - Remove $poster from your Friends list:
    $LJ::SITEROOT/friends/add.bml?user=$poster"
       if LJ::is_friend($u, $self->friend);

    $email .= qq {
  - Edit Friends:
    $LJ::SITEROOT/friends/edit.bml
  - Edit Friends groups:
    $LJ::SITEROOT/friends/editgroups.bml
  - Post an entry
    $LJ::SITEROOT/update.bml};

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $user = $u->ljuser_display;
    my $poster = $self->friend->ljuser_display;
    my $postername = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $journal_profile = $self->friend->profile_url;

    my $email = qq {Hi $user,

$poster has removed you from their Friends list.

You can:
<ul>};

    $email .= "<li><a href=\"$LJ::SITEROOT/friends/add.bml?user=$postername\">Remove $postername from your Friends list</a></li>"
       if LJ::is_friend($u, $self->friend);

    $email .= "<li><a href=\"$LJ::SITEROOT/friends/edit.bml\">Edit Friends</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/friends/editgroups.bml\">Edit Friends groups</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/update.bml\">Post an entry</a></li></ul>";

    return $email;
}

# technically "former friend-of", but who's keeping track.
sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("%s has removed you from their Friends list.",
                   $self->friend->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $u = $self->u;
    my $friend = $self->friend;
    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $friend->addfriend_url . "'>Remove friend</a>"
        if LJ::is_friend($u, $friend);
    $ret .= " <a href='" . $friend->profile_url . "'>View profile</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;
    return sprintf("%s has removed you from their Friends list.",
                   $self->friend->{user});
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal or croak "No user";

    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);

    my $user = $journal_is_owner ? "me" : $journal->ljuser_display;
    return "Someone removes $user from their Friends list";
}

# only users with the track_defriended cap can use this
sub available_for_user  {
    my ($class, $u, $subscr) = @_;
    return $u->get_cap("track_defriended") ? 1 : 0;
}

sub content {
    my ($self) = @_;

    return $self->as_html_actions;
}

1;
