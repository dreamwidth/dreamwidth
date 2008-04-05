# Event that is fired when there is a new post in a journal.
# sarg1 = optional tag id to filter on

package LJ::Event::JournalNewEntry;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->journal, $entry->ditemid);
}

sub is_common { 1 }

sub entry {
    my $self = shift;
    return LJ::Entry->new($self->u, ditemid => $self->arg1);
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $ditemid = $self->arg1;
    my $evtju = $self->event_journal;
    return 0 unless $evtju && $ditemid; # TODO: throw error?

    my $entry = LJ::Entry->new($evtju, ditemid => $ditemid);
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # filter by tag?
    my $stagid = $subscr->arg1;
    if ($stagid) {
        my $usertaginfo = LJ::Tags::get_usertags($entry->journal, {remote => $subscr->owner});

        if ($usertaginfo) {
            my %tagmap = (); # tagname => tagid
            while (my ($tagid, $taginfo) = each %$usertaginfo) {
                $tagmap{$taginfo->{name}} = $tagid;
            }

            return 0 unless grep { $tagmap{$_} == $stagid } $entry->tags;
        }
    }

    # all posts by friends
    return 1 if ! $subscr->journalid && LJ::is_friend($subscr->owner, $self->event_journal);

    # a post on a specific journal
    return LJ::u_equals($subscr->journal, $evtju);
}

sub content {
    my ($self, $target) = @_;
    my $entry = $self->entry;

    return undef unless $entry && $entry->valid;
    return undef unless $entry->visible_to($target);

    return $entry->event_html . $self->as_html_actions;
}

sub as_string {
    my $self = shift;
    my $entry = $self->entry;
    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $poster = $entry->poster->user;
    my $journal = $entry->journal->user;

    return "$poster has posted a new entry$about at " . $entry->url
        if $entry->journal->is_person;

    return "$poster has posted a new entry$about in $journal at " . $entry->url;
}

sub as_sms {
    my $self = shift;

    my $incomm = $self->entry->journal->is_comm ? " in " . $self->entry->journal->user : '';
    sprintf("%s has posted with a new entry$incomm. To view, send READ %s to read it. Standard rates apply.",
            $self->entry->poster->user, $self->entry->journal->user);
}

sub as_html {
    my ($self, $target) = @_;

    croak "No target passed to as_html" unless LJ::isu($target);

    my $journal = $self->u;
    my $entry = $self->entry;

    return sprintf("(Deleted entry in %s)", $journal->ljuser_display)
        unless $entry && $entry->valid;
    return "(You are not authorized to view this entry)"
        unless $self->entry->visible_to($target);

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($entry->poster);
    my $url = $entry->url;

    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $where = LJ::u_equals($journal, $entry->poster) ? "$pu" : "$pu in $ju";

    return "New <a href=\"$url\">entry</a>$about by $where.";
}

sub as_html_actions {
    my ($self) = @_;

    my $entry = $self->entry;
    my $url = $entry->url;
    my $reply_url = $entry->url(mode => 'reply');

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$reply_url'>Reply</a>";
    $ret .= " <a href='$url'>Link</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_email_subject {
    my $self = shift;

    if ($self->entry->journal->is_comm) {
        return $self->entry->poster->display_username . " posted a new entry in " . $self->entry->journal->display_username . "!";
    } else {
        return $self->entry->journal->display_username . " updated their journal!";
    }
}

sub as_email_string {
    my ($self, $u) = @_;
    return unless $self->entry && $self->entry->valid;

    my $username = $u->user;
    my $poster = $self->entry->poster->user;
    my $journal = $self->entry->journal->user;
    my $entry_url = $self->entry->url;
    my $journal_url = $self->entry->journal->journal_base;

    my $email = "Hi $username,\n\n";
    my $about = $self->entry->subject_text ? ' titled "' . $self->entry->subject_text . '"' : '';

    my $tags = '';
    # add tag info for entries that have tags
    if ($self->entry->tags) {
        my @entrytags = $self->entry->tags;
        $tags .= "$_, " foreach @entrytags;
        chop $tags; chop $tags;
        $tags = $tags ? " The entry is tagged \"" . $tags . '".' : '';
    }

    if ($self->entry->journal->is_comm) {
        $email .= "There is a new entry by $poster" . "$about in $journal!$tags\n\n";
    } else {
        $email .= "$poster has posted a new entry$about.$tags\n\n";
    }

    $email .= "You can:

  - View the entry:
    $entry_url";

    if ($self->entry->journal->is_comm) {
        $email .= "
  - Read the recent entries in $journal:
    $journal_url";
        $email .= "
  - Join $journal to read Members-only entries:
    $LJ::SITEROOT/community/join.bml?comm=$journal"
    unless LJ::is_friend($self->entry->journal, $u);
    } else {
        $email .= "
  - Read $poster\'s recent entries:
    $journal_url";
    }

    $email .= "
  - Add $journal to your Friends list:
    $LJ::SITEROOT/friends/add.bml?user=$journal"
      unless LJ::is_friend($u, $self->entry->journal);

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;
    return unless $self->entry && $self->entry->valid;

    my $username = $u->ljuser_display;
    my $poster = $self->entry->poster->ljuser_display;
    my $postername = $self->entry->poster->user;
    my $journal = $self->entry->journal->ljuser_display;
    my $journalname = $self->entry->journal->user;
    my $entry_url = $self->entry->url;
    my $journal_url = $self->entry->journal->journal_base;

    my $email = "Hi $username,\n\n";
    my $about = $self->entry->subject_text ? ' titled "' . $self->entry->subject_text . '"' : '';

    my $tags = '';
    # add tag info for entries with tags
    if ($self->entry->tags) {
        my @entrytags = $self->entry->tags;
        $tags .= "$_, " foreach @entrytags;
        chop $tags; chop $tags;
        $tags = $tags ? " The entry is tagged \"" . $tags . '".' : '';
    }

    if ($self->entry->journal->is_comm) {
        $email .= "There is a new entry by $poster" . "$about in $journal!$tags\n\n";
    } else {
        $email .= "$poster has posted a new entry$about.$tags\n\n";
    }

    $email .= "You can:<ul>";
    $email .= "<li><a href=\"$entry_url\">View the entry</a></li>";

    if ($self->entry->journal->is_comm) {
        $email .= "<li><a href=\"$journal_url\">Read the recent entries in $journalname</a></li>";
        $email .= "<li><a href=\"$LJ::SITEROOT/community/join.bml?comm=$journalname\">Join $journalname to read Members-only entries</a></li>"
            unless LJ::is_friend($self->entry->journal, $u);
    } else {
        $email .= "<li><a href=\"$journal_url\">Read $postername\'s recent entries</a></li>";
    }

    $email .= "<li><a href=\"$LJ::SITEROOT/friends/add.bml?user=$journalname\">Add $journalname to your Friends list</a></li>"
        unless LJ::is_friend($u, $self->entry->journal);
    $email .= "</ul>";

    return $email;
}

sub subscription_applicable {
    my ($class, $subscr) = @_;

    return 1 unless $subscr->arg1;

    # subscription is for entries with tsgs.
    # not applicable if user has no tags
    my $journal = $subscr->journal;

    return 1 unless $journal; # ?

    my $usertags = LJ::Tags::get_usertags($journal);

    if ($usertags && (scalar keys %$usertags)) {
        my @unsub = $class->unsubscribed_tags($subscr);
        return (scalar @unsub) ? 1 : 0;
    }

    return 0;
}

# returns list of (hashref of (tagid => name))
sub unsubscribed_tags {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;
    return () unless $journal;

    my $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner});
    return () unless $usertags;

    my @tagids = sort { $usertags->{$a}->{name} cmp $usertags->{$b}->{name} } keys %$usertags;
    return grep { $_ } map {
        $subscr->owner->has_subscription(
                                         etypeid => $class->etypeid,
                                         arg1    => $_,
                                         journal => $journal
                                         ) ?
                                         undef : {$_ => $usertags->{$_}->{name}};
    } @tagids;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    # are we filtering on a tag?
    my $arg1 = $subscr->arg1;
    if ($arg1 eq '?') {

        my @unsub_tags = $class->unsubscribed_tags($subscr);

        my @tagdropdown;

        foreach my $unsub_tag (@unsub_tags) {
            while (my ($tagid, $name) = each %$unsub_tag) {
                push @tagdropdown, ($tagid, $name);
            }
        }

        my $dropdownhtml = LJ::html_select({
            name => $subscr->freeze('arg1'),
        }, @tagdropdown);

        return "Someone posts an entry tagged $dropdownhtml to " . $journal->ljuser_display
            if $journal->is_comm;
        return $journal->ljuser_display . " posts a new entry tagged $dropdownhtml";
    } elsif ($arg1) {
        my $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner});

        return "Someone posts an entry tagged \"$usertags->{$arg1}->{name}\" to " . $journal->ljuser_display
            if $journal->is_comm;
        return $journal->ljuser_display . " posts a new entry tagged $usertags->{$arg1}->{name}";
    }

    return "Someone on my Friends list posts a new entry" unless $journal;

    return "Someone posts a new entry to " . $journal->ljuser_display
            if $journal->is_comm;
    return $journal->ljuser_display . " posts a new entry.";


}

# when was this entry made?
sub eventtime_unix {
    my $self = shift;
    my $entry = $self->entry;
    return $entry ? $entry->logtime_unix : $self->SUPER::eventtime_unix;
}

sub zero_journalid_subs_means { undef }

1;
