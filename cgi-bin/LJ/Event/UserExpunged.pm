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

package LJ::Event::UserExpunged;
use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ( $class, $u ) = @_;
    croak "No $u" unless $u;

    return $class->SUPER::new($u);
}

sub arg_list {
    return ();
}

sub as_string {
    my $self = shift;
    return $self->event_journal->display_username . " has been purged.";
}

sub as_html {
    my $self = shift;
    return $self->event_journal->ljuser_display . " has been purged.";
}

sub as_html_actions {
    my $self = shift;

    my $ret .= "<div class='actions'>";
    $ret    .= " <a href='$LJ::SITEROOT/rename/'>Rename my account</a>";
    $ret    .= "</div>";

    return $ret;
}

sub as_email_string {
    my ( $self, $u ) = @_;

    my $username   = $u->display_username;
    my $purgedname = $self->event_journal->display_username;

    my $email = qq {Hi $username,

Another set of deleted accounts have just been purged, and the username "$purgedname" is now available.

You can:

  - Rename your account
    $LJ::SITEROOT/rename/};

    return $email;
}

sub as_email_html {
    my ( $self, $u ) = @_;

    my $username   = $u->ljuser_display;
    my $purgedname = $self->event_journal->ljuser_display;

    my $email = qq {Hi $username,

Another set of deleted accounts have just been purged, and the username "$purgedname" is now available.

You can:<ul>};

    $email .= "<li><a href='$LJ::SITEROOT/rename/'>Rename your account</a></li>";
    $email .= "</ul>";

    return $email;
}

sub as_email_subject {
    my $self     = shift;
    my $username = $self->event_journal->user;

    return sprintf "The username '$username' is now available!";
}

sub subscription_as_html {
    my ( $class, $subscr ) = @_;

    my $journal = $subscr->journal;

    my $ljuser = $subscr->journal->ljuser_display;
    return BML::ml( 'event.user_expunged', { user => $ljuser } );    # "$ljuser has been purged";
}

sub content {
    my ( $self, $target ) = @_;

    return $self->as_html_actions;
}

1;
