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

package LJ::Event::NewUserpic;
use strict;
use base 'LJ::Event';
use LJ::Entry;
use Carp qw(croak);

sub new {
    my ( $class, $up ) = @_;
    croak "No userpic" unless $up;

    return $class->SUPER::new( $up->owner, $up->id );
}

sub arg_list {
    return ("Icon id");
}

sub as_string {
    my $self = shift;

    return $self->event_journal->display_username . " has uploaded a new icon.";
}

sub as_html {
    my $self = shift;
    my $up   = $self->userpic;
    return "(Deleted icon)" unless $up && $up->valid;

    return
          $self->event_journal->ljuser_display
        . " has uploaded a new <a href='"
        . $up->url
        . "'>icon</a>.";
}

sub _clean_field {
    my ( $field, %opts ) = @_;

    LJ::CleanHTML::clean(
        \$field,
        {
            wordlength => 40,
            addbreaks  => 0,
            tablecheck => 1,
            mode       => "deny",
            textonly   => $opts{textonly},
        }
    );

    return $field;
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return unless $self->userpic && $self->userpic->valid;

    my $username    = $u->user;
    my $poster      = $self->userpic->owner->user;
    my $userpic     = $self->userpic->url;
    my $comment     = _clean_field( $self->userpic->comment, textonly => 1 ) || '(none)';
    my $description = _clean_field( $self->userpic->description, textonly => 1 ) || '(none)';
    my $journal_url = $self->userpic->owner->journal_base;
    my $icons_url   = $self->userpic->owner->allpics_base;
    my $profile     = $self->userpic->owner->profile_url;

    LJ::text_out( \$comment );
    LJ::text_out( \$description );

    my $email = "Hi $username,

$poster has uploaded a new icon! You can see it at:
   $userpic

Description: $description

Comment: $comment

You can:

  - View all of $poster\'s icons:
    $icons_url";

    unless ( $u->watches( $self->userpic->owner ) ) {
        $email .= "
  - Subscribe to $poster:
    $LJ::SITEROOT/circle/$poster/edit?action=subscribe";
    }

    $email .= "
  - View their journal:
    $journal_url
  - View their profile:
    $profile\n\n";

    return $email;
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return unless $self->userpic && $self->userpic->valid;

    my $username   = $u->ljuser_display;
    my $poster     = $self->userpic->owner->ljuser_display;
    my $postername = $self->userpic->owner->user;
    my $userpic    = $self->userpic->imgtag;

    my $comment     = _clean_field( $self->userpic->comment,     textonly => 0 ) || '(none)';
    my $description = _clean_field( $self->userpic->description, textonly => 0 ) || '(none)';
    my $journal_url = $self->userpic->owner->journal_base;
    my $icons_url   = $self->userpic->owner->allpics_base;
    my $profile     = $self->userpic->owner->profile_url;

    LJ::text_out( \$comment );
    LJ::text_out( \$description );

    my $email = "Hi $username,

$poster has uploaded a new icon:
<blockquote>$userpic</blockquote>
<p>Description: $description</p>
<p>Comment: $comment</p>

You can:<ul>";

    $email .= "<li><a href=\"$icons_url\">View all of $postername\'s icons</a></li>";
    $email .=
"<li><a href=\"$LJ::SITEROOT/circle/$postername/edit?action=subscribe\">Subscribe to $postername</a></li>"
        unless $u->watches( $self->userpic->owner );
    $email .= "<li><a href=\"$journal_url\">View their journal</a></li>";
    $email .= "<li><a href=\"$profile\">View their profile</a></li></ul>";

    return $email;
}

sub userpic {
    my $self = shift;
    my $upid = $self->arg1 or die "No userpic id";
    return eval { LJ::Userpic->new( $self->event_journal, $upid ) };
}

sub content {
    my $self = shift;
    my $up   = $self->userpic;

    return undef unless $up && $up->valid;

    return $up->imgtag;
}

# short enough that we can just use this the normal content as the summary
sub content_summary {
    return $_[0]->content(@_);
}

sub as_email_subject {
    my $self = shift;
    return sprintf "%s uploaded a new icon!", $self->event_journal->display_username;
}

sub zero_journalid_subs_means { "watched" }

sub subscription_as_html {
    my ( $class, $subscr ) = @_;
    my $journal = $subscr->journal;

    # "One of the accounts I subscribe to uploads a new userpic"
    # or "$ljuser uploads a new userpic";
    return $journal
        ? BML::ml( 'event.userpic_upload.user', { user => $journal->ljuser_display } )
        : BML::ml('event.userpic_upload.me');
}

# only users with the track_user_newuserpic cap can use this
sub available_for_user {
    my ( $class, $u, $subscr ) = @_;

    return 0
        if !$u->can_track_new_userpic
        && $subscr->journalid;

    return 1;
}

1;
