# Event that is fired when there is a new post in a journal.
# sarg1 = optional tag id to filter on

package LJ::Event::JournalNewEntry;
use strict;
use Scalar::Util qw(blessed);
use LJ::Entry;
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
    return 1 if ! $subscr->journalid && $subscr->owner->watches( $self->event_journal );

    # a post on a specific journal
    return LJ::u_equals($subscr->journal, $evtju);
}

sub _can_view_content {
    my ( $self, $entry, $target ) = @_;
    
    return undef unless $entry && $entry->valid;
    return undef unless $entry->visible_to( $target );

    return 1;
}

sub content {
    my ($self, $target) = @_;
    my $entry = $self->entry;
    return undef unless $self->_can_view_content( $entry, $target );

    return $entry->event_html . $self->as_html_actions;
}

sub content_summary {
    my ( $self, $target ) = @_;
    
    my $entry = $self->entry;
    return undef unless $self->_can_view_content( $entry, $target );

    my $event_summary = $entry->event_html_summary( 300 );
    my $ret = $event_summary;
    $ret .= "..." if $event_summary ne $entry->event_html;
    $ret .= $self->as_html_actions;

    return $ret;
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

my @_ml_strings_en = (
    'esn.journal_new_entry.posted_new_entry',       # '[[who]] posted a new entry in [[journal]]!',
    'esn.journal_new_entry.updated_their_journal',  # '[[who]] updated their journal!',
    'esn.hi',                                       # 'Hi [[username]],',
    'esn.journal_new_entry.about',                  # ' titled "[[title]]"',
    'esn.tags',                                     # 'The entry is tagged "[[tags]]"',
    'esn.journal_new_entry.head_comm',              # 'There is a new entry by [[poster]][[about]] in [[journal]]![[tags]]',
    'esn.journal_new_entry.head_user',              # '[[poster]] has posted a new entry[[about]].[[tags]]',
    'esn.you_can',                                  # 'You can:',
    'esn.view_entry',                               # '[[openlink]]View the entry[[closelink]]',
    'esn.read_recent_entries',                      # '[[openlink]]Read the recent entries in [[journal]][[closelink]]',
    'esn.join_community',                           # '[[openlink]]Join [[journal]] to read Members-only entries[[closelink]]',
    'esn.read_user_entries',                        # '[[openlink]]Read [[poster]]\'s recent entries[[closelink]]',
    'esn.add_watch'                                 # '[[openlink]]Subscribe to [[journal]][[closelink]]',
);

sub as_email_subject {
    my ($self, $u) = @_;

    # Precache text lines
    my $lang = $u->prop('browselang');
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    if ($self->entry->journal->is_comm) {
        return LJ::Lang::get_text($lang, 'esn.journal_new_entry.posted_new_entry', undef,
            {
                who     => $self->entry->poster->display_username,
                journal => $self->entry->journal->display_username,
            });
    } else {
        return LJ::Lang::get_text($lang, 'esn.journal_new_entry.updated_their_journal', undef,
            {
                who     => $self->entry->journal->display_username,
            });
    }
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $username = $is_html ? $u->ljuser_display : $u->display_username;

    my $poster_text = $self->entry->poster->display_username;
    my $poster      = $is_html ? $self->entry->poster->ljuser_display : $poster_text;

    # $journal - html or plaintext version depends of $is_html
    # $journal_text - text version
    # $journal_user - text version, local journal user (ext_* if OpenId).

    my $journal_text = $self->entry->journal->display_username;
    my $journal = $is_html ? $self->entry->journal->ljuser_display : $journal_text;
    my $journal_user = $self->entry->journal->user;

    my $entry_url   = $self->entry->url;
    my $journal_url = $self->entry->journal->journal_base;

    # Precache text lines
    my $lang = $u->prop('browselang');
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    my $email = LJ::Lang::get_text($lang, 'esn.hi', undef, { username    => $username }) . "\n\n";
    my $about = $self->entry->subject_text ?
        (LJ::Lang::get_text($lang, 'esn.journal_new_entry.about', undef, { title => $self->entry->subject_text })) : '';

    my $tags = '';
    # add tag info for entries that have tags
    if ($self->entry->tags) {
        $tags = ' ' . LJ::Lang::get_text($lang, 'esn.tags', undef, { tags => join(', ', $self->entry->tags ) });
    }

    $email .= LJ::Lang::get_text($lang,
        $self->entry->journal->is_comm ? 'esn.journal_new_entry.head_comm' : 'esn.journal_new_entry.head_user',
        undef,
            {
                poster  => $poster,
                about   => $about,
                journal => $journal,
                tags    => $tags,
            }) . "\n\n";

    # make hyperlinks for options
    # tags 'poster' and 'journal' cannot contain html <a> tags
    # when it used between [[openlink]] and [[closelink]] tags.
    my $vars = {
                poster  => $poster_text,
                journal => $journal_text,
            };

    $email .= LJ::Lang::get_text($lang, 'esn.you_can', undef) .
        $self->format_options($is_html, $lang, $vars,
            {
                'esn.view_entry'            => [ 1, $entry_url ],
                'esn.read_recent_entries'   => [ $self->entry->journal->is_comm ? 2 : 0,
                                                    $journal_url ],
                'esn.join_community'        => [ ($self->entry->journal->is_comm && !$u->member_of( $self->entry->journal )) ? 3 : 0,
                                                    "$LJ::SITEROOT/community/join?comm=$journal_user" ],
                'esn.read_user_entries'     => [ ($self->entry->journal->is_comm) ? 0 : 4,
                                                    $journal_url ],
                'esn.add_watch'             => [ $u->watches( $self->entry->journal ) ? 0 : 5,
                                                    "$LJ::SITEROOT/manage/circle/add?user=$journal_user&action=subscribe" ],
            });

    return $email;
}

sub as_email_string {
    my ($self, $u) = @_;
    return unless $self->entry && $self->entry->valid;

    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return unless $self->entry && $self->entry->valid;

    return _as_email($self, $u, 1);
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
    my $usertags;

    if ($arg1 eq '?') {
        my @unsub_tags = $class->unsubscribed_tags($subscr);
        my @tagdropdown;

        foreach my $unsub_tag (@unsub_tags) {
            while (my ($tagid, $name) = each %$unsub_tag) {
                push @tagdropdown, ($tagid, $name);
            }
        }

        $usertags = LJ::html_select({
            name => $subscr->freeze('arg1'),
        }, @tagdropdown);

    } elsif ($arg1) {
        $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner})->{$arg1}->{'name'};
    }

    if ($arg1) {
        return BML::ml('event.journal_new_entry.tag.' . ($journal->is_comm ? 'community' : 'user'),
                {
                    user    => $journal->ljuser_display,
                    tags    => $usertags,
                });
    }

    return BML::ml('event.journal_new_entry.friendlist') unless $journal;

    return BML::ml('event.journal_new_entry.' . ($journal->is_comm ? 'community' : 'user'),
            {
                user    => $journal->ljuser_display,
            });
}

# when was this entry made?
sub eventtime_unix {
    my $self = shift;
    my $entry = $self->entry;
    return $entry ? $entry->logtime_unix : $self->SUPER::eventtime_unix;
}

sub zero_journalid_subs_means { undef }

1;
