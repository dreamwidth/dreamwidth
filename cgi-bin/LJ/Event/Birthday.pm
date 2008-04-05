package LJ::Event::Birthday;

use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ($class, $u) = @_;
    croak "No user" unless $u && LJ::isu($u);

    return $class->SUPER::new($u);
}

sub bdayuser {
    my $self = shift;
    return $self->event_journal;
}

# formats birthday as "August 1"
sub bday {
    my $self = shift;
    my ($year, $mon, $day) = split(/-/, $self->bdayuser->{bdate});

    my @months = qw(January February March April May June
                    July August September October November December);

    return "$months[$mon-1] $day";
}

sub matches_filter {
    my ($self, $subscr) = @_;

    return $self->bdayuser->can_show_bday(to => $subscr->owner) ? 1 : 0;
}

sub as_string {
    my $self = shift;

    return sprintf("%s's birthday is on %s!",
                   $self->bdayuser->display_username,
                   $self->bday);
}

sub as_html {
    my $self = shift;

    return sprintf("%s's birthday is on %s!",
                   $self->bdayuser->ljuser_display,
                   $self->bday);
}

sub as_html_actions {
    my ($self) = @_;

    my $gifturl = $self->bdayuser->gift_url({ item => 'vgift' });
    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$gifturl'>Send a Gift</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_email_subject {
    my $self = shift;

    return sprintf("%s's birthday is coming up!",
                   $self->bdayuser->display_username);
}

sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->user;
    my $bdayuser = $self->bdayuser->display_username;
    my $bday = $self->bday;

    my $email = qq {Hi $username,

$bdayuser\'s birthday is coming up on $bday!

You can:
  - Post to wish them a happy birthday
    $LJ::SITEROOT/update.bml};

    $email .= LJ::run_hook('birthday_notif_extra_plaintext', $u) || "";

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $bdayuser = $self->bdayuser->ljuser_display;
    my $bday = $self->bday;

    my $email = qq {Hi $username,

$bdayuser\'s birthday is coming up on $bday!

You can:<ul>};

    $email .= "<li><a href=\"$LJ::SITEROOT/update.bml\">"
           . "Post to wish them a happy birthday</a></li>";

    $email .= LJ::run_hook('birthday_notif_extra_html', $u) || "";

    $email .= "</ul>";

    return $email;
}


sub zero_journalid_subs_means { "friends" }

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    return "One of my friends has an upcoming birthday"
        unless $journal;

    my $ljuser = $journal->ljuser_display;
    return "$ljuser\'s birthday is coming up";
}

sub content {
    my ($self, $target) = @_;

    return $self->as_html_actions;
}

1;
