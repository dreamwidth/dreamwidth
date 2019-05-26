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

# Event that is fired when there is a new post in a journal.
# sarg1 = optional tag id to filter on
# sarg2 = optional poster id to filter on (in a community)

package LJ::Event::JournalNewEntry;
use strict;
use Scalar::Util qw(blessed);
use LJ::Entry;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ( $class, $entry ) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new( $entry->journal, $entry->ditemid );
}

sub arg_list {
    return ("Entry ditemid");
}

sub is_common { 1 }

sub entry {
    my $self = shift;
    return LJ::Entry->new( $self->u, ditemid => $self->arg1 );
}

sub matches_filter {
    my ( $self, $subscr ) = @_;

    return 0 unless $subscr->available_for_user;

    my $ditemid = $self->arg1;
    my $evtju   = $self->event_journal;
    return 0 unless $evtju && $ditemid;    # TODO: throw error?

    my $entry = LJ::Entry->new( $evtju, ditemid => $ditemid );
    return 0 unless $entry && $entry->valid;                # TODO: throw error?
    return 0 unless $entry->visible_to( $subscr->owner );

    # filter by tag?
    my $stagid = $subscr->arg1;
    if ($stagid) {
        my $usertaginfo = LJ::Tags::get_usertags( $entry->journal, { remote => $subscr->owner } );

        if ($usertaginfo) {
            my %tagmap = ();                                # tagname => tagid
            while ( my ( $tagid, $taginfo ) = each %$usertaginfo ) {
                $tagmap{ $taginfo->{name} } = $tagid;
            }

            return 0 unless grep { $tagmap{$_} == $stagid } $entry->tags;
        }
    }

    # filter by user?
    my $suserid = $subscr->arg2;
    my $su      = LJ::load_userid($suserid);
    if ($su) {
        return 0 unless $subscr->journalid && $entry->poster->equals($su);
    }

    # all posts by friends
    return 1 if !$subscr->journalid && $subscr->owner->watches( $self->event_journal );

    # a post on a specific journal
    return $evtju->equals( $subscr->journal );
}

sub _can_view_content {
    my ( $self, $entry, $target ) = @_;

    return undef unless $entry && $entry->valid;
    return undef unless $entry->visible_to($target);

    return 1;
}

sub content {
    my ( $self, $target ) = @_;
    my $entry = $self->entry;
    return undef unless $self->_can_view_content( $entry, $target );

    my $entry_body = $entry->event_html(
        {
            # double negatives, ouch!
            ljcut_disable => !$target->cut_inbox,
            cuturl        => $entry->url,
            sandbox       => 1,
            preformatted  => $entry->prop("opt_preformatted"),
        }
    ) . $self->as_html_tags($target);

    $entry_body = "<div class='actions_top'>" . $self->as_html_actions . "</div>" . $entry_body
        if LJ::has_too_many( $entry_body, linebreaks => 10, chars => 2000 );
    $entry_body .= $self->as_html_actions;

    my $admin_post = "";
    if ( $entry->admin_post ) {
        $admin_post = '<div class="AdminPost">'
            . LJ::Lang::get_default_text( "esn.journal_new_entry.admin_post",
            { img => LJ::img('admin-post') } )
            . '</div>';
    }

    return $admin_post . $entry_body;
}

sub as_html_tags {
    my ( $self, $u ) = @_;
    my $tags = '';
    my $url  = $self->entry->journal->journal_base;

    my @taglist = $self->entry->tags;

    # add tag info for entries that have tags
    if (@taglist) {
        my @htmltags = ();
        push @htmltags, qq{<a href="$url/tag/$_">$_</a>} foreach @taglist;

        $tags =
              "<div class='entry-tags'>"
            . LJ::Lang::get_default_text( 'esn.tags.short', { tags => join( ', ', @htmltags ) } )
            . "</div>";
    }
    return $tags;

}

sub content_summary {
    my ( $self, $target ) = @_;

    my $entry = $self->entry;
    return undef unless $self->_can_view_content( $entry, $target );

    my $truncated;
    my $event_summary = $entry->event_html_summary( 300, { cuturl => $entry->url }, \$truncated );
    my $ret           = $event_summary;
    $ret .= "..." if $truncated;
    $ret .= $self->as_html_actions;

    return $ret;
}

sub as_string {
    my $self    = shift;
    my $entry   = $self->entry;
    my $about   = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $poster  = $entry->poster->user;
    my $journal = $entry->journal->user;

    return "$poster has posted a new entry$about at " . $entry->url
        if $entry->journal->is_person;

    return "$poster has posted a new entry$about in $journal at " . $entry->url;
}

sub as_html {
    my ( $self, $target ) = @_;

    croak "No target passed to as_html" unless LJ::isu($target);

    my $journal = $self->u;
    my $entry   = $self->entry;

    return sprintf( "(Deleted entry in %s)", $journal->ljuser_display )
        unless $entry && $entry->valid;
    return "(You are not authorized to view this entry)"
        unless $self->entry->visible_to($target);

    my $ju  = LJ::ljuser($journal);
    my $pu  = LJ::ljuser( $entry->poster );
    my $url = $entry->url;

    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $where = $journal->equals( $entry->poster ) ? "$pu" : "$pu in $ju";

    return "New <a href=\"$url\">entry</a>$about by $where.";
}

sub as_html_actions {
    my ($self) = @_;

    my $entry     = $self->entry;
    my $url       = $entry->url;
    my $reply_url = $entry->url( mode => 'reply' );

    my $ret .= "<div class='actions'>";
    $ret    .= " <a href='$reply_url'>Reply</a> |";
    $ret    .= " <a href='$url'>Link</a>";
    $ret    .= "</div>";

    return $ret;
}

my @_ml_strings_en = (
    'esn.journal_new_entry.posted_new_entry',        # '[[who]] posted a new entry in [[journal]]!',
    'esn.journal_new_entry.updated_their_journal',   # '[[who]] updated their journal!',
    'esn.hi',                                        # 'Hi [[username]],',
    'esn.journal_new_entry.about',                   # ' titled "[[title]]"',
    'esn.tags',                                      # 'The entry is tagged "[[tags]]"',
    'esn.tags.short',
    'esn.journal_new_entry.head_comm2'
    ,    # 'There is a new entry by [[poster]][[about]][[postsecurity]] in [[journal]]![[tags]]',
    'esn.journal_new_entry.head_user2'
    ,                 # '[[poster]] has posted a new entry[[about]][[postsecurity]].[[tags]]',
    'esn.you_can',    # 'You can:',
    'esn.view_entry.nosubject', # '[[openlink]]View entry [[ditemid]][[closelink]]'
    'esn.view_entry.subject',   # '[[openlink]]View entry titled [[subject]][[closelink]]',
    'esn.reply_to_entry',       # '[[openlink]]Leave a reply to this entry[[closelink]]',
    'esn.read_recent_entries',  # '[[openlink]]Read the recent entries in [[journal]][[closelink]]',
    'esn.join_community'
    ,    # '[[openlink]]Join [[journal]] to read Members-only entries[[closelink]]',
    'esn.read_user_entries',    # '[[openlink]]Read [[poster]]\'s recent entries[[closelink]]',
    'esn.add_watch'             # '[[openlink]]Subscribe to [[journal]][[closelink]]',
);

sub as_email_subject {
    my ( $self, $u ) = @_;

    # Precache text lines
    LJ::Lang::get_default_text_multi( \@_ml_strings_en );

    if ( $self->entry->journal->is_comm ) {
        return LJ::Lang::get_default_text(
            'esn.journal_new_entry.posted_new_entry',
            {
                who     => $self->entry->poster->display_username,
                journal => $self->entry->journal->display_username,
            }
        );
    }
    else {
        return LJ::Lang::get_default_text(
            'esn.journal_new_entry.updated_their_journal',
            {
                who => $self->entry->journal->display_username,
            }
        );
    }
}

sub _as_email {
    my ( $self, $u, $is_html ) = @_;

    my $username = $is_html ? $u->ljuser_display : $u->display_username;

    my $poster_text = $self->entry->poster->display_username;
    my $poster      = $is_html ? $self->entry->poster->ljuser_display : $poster_text;

    # $journal - html or plaintext version depends of $is_html
    # $journal_text - text version
    # $journal_user - text version, local journal user (ext_* if OpenId).

    my $journal_text = $self->entry->journal->display_username;
    my $journal      = $is_html ? $self->entry->journal->ljuser_display : $journal_text;
    my $journal_user = $self->entry->journal->user;

    my $entry_url   = $self->entry->url;
    my $journal_url = $self->entry->journal->journal_base;

    my $subject_text = $self->entry->subject_text;

    # Precache text lines, using DEFAULT_LANG for $u
    my $lang = $LJ::DEFAULT_LANG;
    LJ::Lang::get_text_multi( $lang, undef, \@_ml_strings_en );

    my $email = LJ::Lang::get_text( $lang, 'esn.hi', undef, { username => $username } ) . "\n\n";
    my $about =
        $subject_text
        ? (
        LJ::Lang::get_text(
            $lang, 'esn.journal_new_entry.about',
            undef, { title => $self->entry->subject_text }
        )
        )
        : '';

    my $tags = '';

    # add tag info for entries that have tags
    if ( $self->entry->tags ) {
        $tags = ' '
            . LJ::Lang::get_text( $lang, 'esn.tags', undef,
            { tags => join( ', ', $self->entry->tags ) } );
    }

    # indicate post security if it is locked or filtered
    my $postsecurity = '';
    if ( $self->entry->security eq 'usemask' ) {
        $postsecurity = ' [locked]';
    }

    my $head_ml = 'esn.journal_new_entry.head_user2';
    my $entry   = $self->entry;
    if ( $entry->journal->is_comm ) {
        $head_ml = 'esn.journal_new_entry.head_comm2';

        $head_ml .= '.admin_post'
            if $entry->admin_post;
    }

    $email .= LJ::Lang::get_text(
        $lang, $head_ml, undef,
        {
            poster  => $poster,
            about   => $about,
            journal => $journal,
            tags    => $tags,
        }
    ) . "\n\n";

    # make hyperlinks for options
    # tags 'poster' and 'journal' cannot contain html <a> tags
    # when it used between [[openlink]] and [[closelink]] tags.
    my $vars = {
        poster  => $poster_text,
        journal => $journal_text,
        ditemid => $self->entry->ditemid,
        subject => $subject_text,
    };

    my $has_subject = $subject_text ? "subject" : "nosubject";
    $email .= LJ::Lang::get_text( $lang, 'esn.you_can', undef )
        . $self->format_options(
        $is_html, $lang, $vars,
        {
            "esn.view_entry.$has_subject" => [ 1, $entry_url ],
            'esn.reply_to_entry'          => [ 2, "$entry_url?mode=reply" ],
            'esn.read_recent_entries' => [ $self->entry->journal->is_comm ? 3 : 0, $journal_url ],
            'esn.join_community'      => [
                ( $self->entry->journal->is_comm && !$u->member_of( $self->entry->journal ) )
                ? 4
                : 0,
                "$LJ::SITEROOT/circle/$journal_user/edit"
            ],
            'esn.read_user_entries' => [ ( $self->entry->journal->is_comm ) ? 0 : 5, $journal_url ],
            'esn.add_watch'         => [
                $u->watches( $self->entry->journal ) ? 0 : 6,
                "$LJ::SITEROOT/circle/$journal_user/edit?action=subscribe"
            ],
        }
        );

    return $email;
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return unless $self->entry && $self->entry->valid;

    return _as_email( $self, $u, 0 );
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return unless $self->entry && $self->entry->valid;

    return _as_email( $self, $u, 1 );
}

sub subscription_applicable {
    my ( $class, $subscr ) = @_;

    return 1 unless $subscr->arg1;

    # subscription is for entries with tags.
    # not applicable if user has no tags
    my $journal = $subscr->journal;

    return 1 unless $journal;    # ?

    my $usertags = LJ::Tags::get_usertags($journal);

    if ( $usertags && ( scalar keys %$usertags ) ) {
        my @unsub = $class->unsubscribed_tags($subscr);
        return ( scalar @unsub ) ? 1 : 0;
    }

    return 0;
}

# returns list of (hashref of (tagid => name))
sub unsubscribed_tags {
    my ( $class, $subscr ) = @_;

    my $journal = $subscr->journal;
    return () unless $journal;

    my $usertags = LJ::Tags::get_usertags( $journal, { remote => $subscr->owner } );
    return () unless $usertags;

    my @tagids = sort { $usertags->{$a}->{name} cmp $usertags->{$b}->{name} } keys %$usertags;
    return grep { $_ } map {
        $subscr->owner->has_subscription(
            etypeid => $class->etypeid,
            arg1    => $_,
            journal => $journal
        ) ? undef : { $_ => $usertags->{$_}->{name} };
    } @tagids;
}

sub subscription_as_html {
    my ( $class, $subscr ) = @_;

    my $journal = $subscr->journal;

    # are we filtering on a tag?
    my $arg1 = $subscr->arg1;
    my $usertags;

    if ( $arg1 eq '?' ) {
        my @unsub_tags = $class->unsubscribed_tags($subscr);
        my %entry_tags = $subscr->entry ? map { $_ => 1 } $subscr->entry->tags : ();

        my @entrytagdropdown;
        my @fulltagdropdown;

        foreach my $unsub_tag (@unsub_tags) {
            while ( my ( $tagid, $name ) = each %$unsub_tag ) {
                if ( $entry_tags{$name} ) {
                    push @entrytagdropdown, { value => $tagid, text => $name };
                }
                else {
                    push @fulltagdropdown, { value => $tagid, text => $name };
                }
            }
        }

        my @tagdropdown;

        if (@entrytagdropdown) {
            @tagdropdown = (
                {
                    optgroup => LJ::Lang::ml('event.journal_new_entry.taglist.entry'),
                    items    => \@entrytagdropdown
                },
                {
                    optgroup => LJ::Lang::ml('event.journal_new_entry.taglist.full'),
                    items    => \@fulltagdropdown
                },
            );
        }
        else {
            @tagdropdown = @fulltagdropdown;
        }

        $usertags = LJ::html_select(
            {
                name => $subscr->freeze('arg1'),
            },
            @tagdropdown
        );

    }
    elsif ($arg1) {
        $usertags =
            LJ::Tags::get_usertags( $journal, { remote => $subscr->owner } )->{$arg1}->{'name'};
    }

    if ($arg1) {
        return BML::ml(
            'event.journal_new_entry.tag.' . ( $journal->is_comm ? 'community' : 'user' ),
            {
                user => $journal->ljuser_display,
                tags => $usertags,
            }
        );
    }

    # are we filtering on a poster?
    my $arg2 = $subscr->arg2;

    if ($arg2) {
        my $postu = LJ::load_userid($arg2);
        if ($postu) {
            return BML::ml(
                'event.journal_new_entry.poster',
                {
                    user   => $journal->ljuser_display,
                    poster => $postu->ljuser_display,
                }
            );
        }
    }

    return BML::ml('event.journal_new_entry.friendlist') unless $journal;

    return BML::ml(
        'event.journal_new_entry.' . ( $journal->is_comm ? 'community' : 'user' ),
        {
            user => $journal->ljuser_display,
        }
    );
}

# when was this entry made?
sub eventtime_unix {
    my $self  = shift;
    my $entry = $self->entry;
    return $entry ? $entry->logtime_unix : $self->SUPER::eventtime_unix;
}

sub zero_journalid_subs_means { undef }

1;
