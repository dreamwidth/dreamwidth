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

package LJ::Event::JournalNewComment;
use strict;
use Scalar::Util qw(blessed);
use LJ::Comment;
use DW::EmailPost::Comment;
use Carp qw(croak);
use base 'LJ::Event';

# we don't allow subscriptions to comments on friends' journals, so
# setting undef on this skips some nasty queries
sub zero_journalid_subs_means { undef }

sub new {
    my ( $class, $comment ) = @_;
    croak 'Not an LJ::Comment' unless blessed $comment && $comment->isa("LJ::Comment");
    return $class->SUPER::new( $comment->journal, $comment->jtalkid );
}

sub arg_list {
    return ("Comment jtalkid");
}

sub related_event_classes {
    return (
        "LJ::Event::JournalNewComment",         "LJ::Event::JournalNewComment::TopLevel",
        "LJ::Event::JournalNewComment::Edited", "LJ::Event::JournalNewComment::Reply"
    );
}

sub is_common { 1 }

my @_ml_strings_en = (
    'esn.mail_comments.fromname.user',         # "[[user]] - [[sitenameabbrev]] Comment",
    'esn.mail_comments.fromname.anonymous',    # "[[sitenameshort]] Comment",
    'esn.mail_comments.subject.edit_reply_to_your_comment',    # "Edited reply to your comment...",
    'esn.mail_comments.subject.reply_to_your_comment',         # "Reply to your comment...",
    'esn.mail_comments.subject.edit_reply_to_your_entry',      # "Edited reply to your entry...",
    'esn.mail_comments.subject.reply_to_your_entry',           # "Reply to your entry...",
    'esn.mail_comments.subject.edit_reply_to_an_entry',        # "Edited reply to an entry...",
    'esn.mail_comments.subject.reply_to_an_entry',             # "Reply to an entry...",
    'esn.mail_comments.subject.edit_reply_to_a_comment',       # "Edited reply to a comment...",
    'esn.mail_comments.subject.reply_to_a_comment',            # "Reply to a comment...",
    'esn.mail_comments.subject.comment_you_posted',            # "Comment you posted...",
    'esn.mail_comments.subject.comment_you_edited',            # "Comment you edited...",
);

sub as_email_from_name {
    my ( $self, $u ) = @_;

    my $vars = {
        user           => $self->comment->poster ? $self->comment->poster->display_username : '',
        sitenameabbrev => $LJ::SITENAMEABBREV,
        sitenameshort  => $LJ::SITENAMESHORT,
    };

    my $key = 'esn.mail_comments.fromname.';
    if ( $self->comment->poster ) {
        $key .= 'user';
    }
    else {
        $key .= 'anonymous';
    }

    return LJ::Lang::get_default_text( $key, $vars );
}

sub as_email_headers {
    my ( $self, $u ) = @_;

    my $this_msgid = $self->comment->email_messageid;
    my $top_msgid  = $self->comment->entry->email_messageid;

    my $par_msgid;
    if ( $self->comment->parent ) {    # a reply to a comment
        $par_msgid = $self->comment->parent->email_messageid;
    }
    else {                             # reply to an entry
        $par_msgid = $top_msgid;
        $top_msgid = "";               # so it's not duplicated
    }

    my $journalu = $self->comment->entry->journal;
    my $headers  = {
        'Message-ID'     => $this_msgid,
        'In-Reply-To'    => $par_msgid,
        'References'     => "$top_msgid $par_msgid",
        'X-Journal-Name' => $journalu->user,
        'Reply-To'       => DW::EmailPost::Comment->replyto_address_header(
            $u, $journalu,
            $self->comment->entry->ditemid,
            $self->comment->dtalkid
        ),
    };

    return $headers;

}

sub as_email_subject {
    my ( $self, $u ) = @_;

    my $edited = $self->comment->is_edited;

    my $entry_details = '';
    if ( $self->comment->journal && $self->comment->entry ) {
        $entry_details = ' [ '
            . $self->comment->journal->display_name . ' - '
            . $self->comment->entry->ditemid . ' ]';
    }

    my $key = 'esn.mail_comments.subject.';
    if ( $self->comment->subject_orig ) {
        return LJ::strip_html( $self->comment->subject_orig . $entry_details );
    }
    elsif ( $u && $u->equals( $self->comment->poster ) ) {
        $key .= $edited ? 'comment_you_edited' : 'comment_you_posted';
    }
    elsif ( $self->comment->parent ) {
        if ( $u && $u->equals( $self->comment->parent->poster ) ) {
            $key .= $edited ? 'edit_reply_to_your_comment' : 'reply_to_your_comment';
        }
        else {
            $key .= $edited ? 'edit_reply_to_a_comment' : 'reply_to_a_comment';
        }
    }
    elsif ( $u && $u->equals( $self->comment->entry->poster ) ) {
        $key .= $edited ? 'edit_reply_to_your_entry' : 'reply_to_your_entry';
    }
    else {
        $key .= $edited ? 'edit_reply_to_an_entry' : 'reply_to_an_entry';
    }

    return LJ::Lang::get_default_text($key) . $entry_details;
}

sub as_email_string {
    my ( $self, $u ) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    return $comment->format_text_mail($u);
}

sub as_email_html {
    my ( $self, $u ) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    return $comment->format_html_mail($u);
}

sub as_string {
    my ( $self, $u ) = @_;
    my $comment = $self->comment;
    my $journal = $comment->entry->journal->user;

    return "There is a new anonymous comment in $journal at " . $comment->url
        unless $comment->poster;

    my $poster = $comment->poster->display_username;
    if ( $self->comment->is_edited ) {
        return "$poster has edited a comment in $journal at " . $comment->url;
    }
    else {
        return "$poster has posted a new comment in $journal at " . $comment->url;
    }
}

sub _can_view_content {
    my ( $self, $comment, $target ) = @_;

    return undef unless $comment        && $comment->valid;
    return undef unless $comment->entry && $comment->entry->valid;
    return undef unless $comment->visible_to($target);
    return undef if $comment->is_deleted;

    return 1;
}

sub content {
    my ( $self, $target ) = @_;

    my $comment = $self->comment;
    return undef unless $self->_can_view_content( $comment, $target );

    LJ::need_res('js/commentmanage.js');

    my $comment_body = $comment->body_html;
    my $buttons      = $comment->manage_buttons;
    my $dtalkid      = $comment->dtalkid;
    my $htmlid       = LJ::Talk::comment_htmlid($dtalkid);

    $comment_body = LJ::html_newlines($comment_body);

    if ( $comment->is_edited ) {
        my $reason = LJ::ehtml( $comment->edit_reason );
        $comment_body .= "<br /><br /><div class='edittime'>"
            . LJ::Lang::get_default_text( "esn.journal_new_comment.edit_reason",
            { reason => $reason } )
            . "</div>"
            if $reason;
    }

    my $admin_post = "";

    if ( $comment->admin_post ) {
        $admin_post = '<div class="AdminPost">'
            . LJ::Lang::get_default_text( "esn.journal_new_comment.admin_post",
            { img => LJ::img('admin-post') } )
            . '</div>';
    }

    my $ret = qq {
        <div id="$htmlid" class="JournalNewComment">
            <div class="ManageButtons">$buttons</div>
            $admin_post
            <div class="Body">$comment_body</div>
        </div>
    };

    my $cmt_info = $comment->info;
    $cmt_info->{form_auth} = LJ::form_auth(1);
    my $cmt_info_js = LJ::js_dumper($cmt_info) || '{}';

    my $posterusername = $self->comment->poster ? $self->comment->poster->{user} : "";

    $ret .= qq {
        <script language="JavaScript">
        };

    while ( my ( $k, $v ) = each %$cmt_info ) {
        $k = LJ::ejs($k);
        $v = LJ::ejs($v);
        $ret .= "LJ_cmtinfo['$k'] = '$v';\n";
    }

    my $dtid_cmt_info = { u => $posterusername, rc => [] };

    $ret .= "LJ_cmtinfo['$dtalkid'] = " . LJ::js_dumper($dtid_cmt_info) . "\n";

    $ret .= qq {
        </script>
        };

    $ret = "<div class='actions_top'>" . $self->as_html_actions . "</div>" . $ret
        if LJ::has_too_many( $comment_body, linebreaks => 10, chars => 2000 );

    $ret .= $self->as_html_actions;

    return $ret;
}

sub content_summary {
    my ( $self, $target ) = @_;

    my $comment = $self->comment;
    return undef unless $self->_can_view_content( $comment, $target );

    my $body_summary = $comment->body_html_summary(300);
    my $ret          = $body_summary;
    $ret .= "..." if $comment->body_html ne $body_summary;

    if ( $comment->is_edited ) {
        my $reason = LJ::ehtml( $comment->edit_reason );
        $ret .= "<br /><br /><div class='edittime'>"
            . LJ::Lang::get_default_text( "esn.journal_new_comment.edit_reason",
            { reason => $reason } )
            . "</div>"
            if $reason;
    }

    $ret .= $self->as_html_actions;

    return $ret;
}

sub as_html {
    my ( $self, $target ) = @_;

    my $comment = $self->comment;
    my $journal = $self->u;

    my $entry = $comment->entry;
    return sprintf( "(Comment on a deleted entry in %s)", $journal->ljuser_display )
        unless $entry && $entry->valid;

    my $entry_subject = $entry->subject_text || "an entry";
    return sprintf(
        qq{(Deleted comment to post from %s in %s: comment by %s in "%s")},
        LJ::diff_ago_text( $entry->logtime_unix ),
        $journal->ljuser_display,
        $comment->poster ? $comment->poster->ljuser_display : "(Anonymous)",
        $entry_subject
    ) unless $comment && $comment->valid && !$comment->is_deleted;

    return "(You are not authorized to view this comment)" unless $comment->visible_to($target);

    my $ju  = LJ::ljuser($journal);
    my $pu  = LJ::ljuser( $comment->poster );
    my $url = $comment->url;

    my $in_text = '<a href="' . $entry->url . "\">$entry_subject</a>";
    my $subject = $comment->subject_text ? ' "' . $comment->subject_text . '"' : '';

    my $poster = $comment->poster ? "by $pu" : '';
    my $ret;
    if ( $comment->is_edited ) {
        $ret = "Edited <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";
    }
    else {
        $ret = "New <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";
    }

    $ret .=
          ' <span class="filterlink_singleentry">(<a href="/inbox/?view=singleentry&itemid='
        . $entry->ditemid
        . '">filter to this entry</a>)</span>';
}

sub as_html_actions {
    my ($self) = @_;

    my $comment    = $self->comment;
    my $url        = $comment->url;
    my $reply_url  = $comment->reply_url;
    my $parent_url = $comment->parent_url;

    my $ret .= "<div class='actions'>";
    $ret    .= " <a href='$reply_url'>Reply</a> | ";
    $ret    .= " <a href='$url'>Link</a> ";
    $ret    .= " | <a href='$parent_url'>Parent</a>" if $parent_url;
    $ret    .= "</div>";

    return $ret;
}

# ML-keys and contents of all items used in this subroutine:
# 01 event.journal_new_comment.friend=Someone comments in any journal on my friends page
# 02 event.journal_new_comment.my_journal=Someone comments in my journal, on any entry
# 03 event.journal_new_comment.user_journal=Someone comments in [[user]], on any entry
# 04 event.journal_new_comment.user_journal.deleted=Someone comments on a deleted entry in [[user]]
# 05 event.journal_new_comment.my_journal.deleted=Someone comments on a deleted entry in my journal
# 06 event.journal_new_comment.user_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 07 event.journal_new_comment.user_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> in [[user]]
# 08 event.journal_new_comment.my_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> my journal
# 09 event.journal_new_comment.my_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> my journal
# 10 event.journal_new_comment.my_journal.titled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 11 event.journal_new_comment.my_journal.titled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 12 event.journal_new_comment.my_journal.titled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 13 event.journal_new_comment.my_journal.titled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 14 event.journal_new_comment.my_journal.titled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 15 event.journal_new_comment.my_journal.titled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> on my journal
# 16 event.journal_new_comment.my_journal.untitled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> on my journal
# 17 event.journal_new_comment.my_journal.untitled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> on my journal
# 18 event.journal_new_comment.my_journal.untitled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>en entry</a> on my journal
# 19 event.journal_new_comment.my_journal.untitled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>en entry</a> on my journal
# 20 event.journal_new_comment.my_journal.untitled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> on my journal
# 21 event.journal_new_comment.my_journal.untitled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> on my journal
# 22 event.journal_new_comment.user_journal.titled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 23 event.journal_new_comment.user_journal.titled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 24 event.journal_new_comment.user_journal.titled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 25 event.journal_new_comment.user_journal.titled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 26 event.journal_new_comment.user_journal.titled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 27 event.journal_new_comment.user_journal.titled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
# 28 event.journal_new_comment.user_journal.untitled_entry.titled_thread.user=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 29 event.journal_new_comment.user_journal.untitled_entry.untitled_thread.user=Someone comments under <a href='[[threadurl]]'>the thread</a> by [[posteruser]] in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 30 event.journal_new_comment.user_journal.untitled_entry.titled_thread.me=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by me in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 31 event.journal_new_comment.user_journal.untitled_entry.untitled_thread.me=Someone comments under <a href='[[threadurl]]'>the thread</a> by me in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 32 event.journal_new_comment.user_journal.untitled_entry.titled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>[[thread_desc]]</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> in [[user]]
# 33 event.journal_new_comment.user_journal.untitled_entry.untitled_thread.anonymous=Someone comments under <a href='[[threadurl]]'>the thread</a> by (Anonymous) in <a href='[[entryurl]]'>en entry</a> in [[user]]
# -- now, let's begin.
sub subscription_as_html {
    my ( $class, $subscr, $key_prefix ) = @_;

    my $arg1    = $subscr->arg1;
    my $arg2    = $subscr->arg2;
    my $journal = $subscr->journal;

    my $key = $key_prefix || 'event.journal_new_comment';

    if ( !$journal ) {
### 01 event.journal_new_comment.friend=Someone comments in any journal on my friends page
        return BML::ml( $key . '.friend' );
    }

    my ( $user, $journal_is_owner );
    if ( $journal->equals( $subscr->owner ) ) {
        $user = 'my journal';
        $key .= '.my_journal';
        my $journal_is_owner = 1;
    }
    else {
        $user = LJ::ljuser($journal);
        $key .= '.user_journal';
        my $journal_is_owner = 0;
    }

    return if $journal->is_identity;

    if ( $arg1 == 0 && $arg2 == 0 ) {
### 02 event.journal_new_comment.my_journal=Someone comments in my journal, on any entry
### 03 event.journal_new_comment.user_journal=Someone comments in [[user]], on any entry
        return BML::ml( $key, { user => $user } );
    }

    # load ditemid from jtalkid if no ditemid
    my $comment;
    if ($arg2) {
        $comment = LJ::Comment->new( $journal, jtalkid => $arg2 );
        return "(Invalid comment)" unless $comment && $comment->valid;
        $arg1 = $comment->entry->ditemid unless $arg1;
    }

    my $entry = LJ::Entry->new( $journal, ditemid => $arg1 );
### 04 event.journal_new_comment.user_journal.deleted=Someone comments on a deleted entry in [[user]]
### 05 event.journal_new_comment.my_journal.deleted=Someone comments on a deleted entry in my journal
    return BML::ml( $key . '.deleted', { user => $user } ) unless $entry && $entry->valid;

    my $entrydesc = $entry->subject_text;
    if ($entrydesc) {
        $entrydesc = "\"$entrydesc\"";
        $key .= '.titled_entry';
    }
    else {
        $entrydesc = "an entry";
        $key .= '.untitled_entry';
    }

    my $entryurl = $entry->url;
### 06 event.journal_new_comment.user_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
### 07 event.journal_new_comment.user_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> in [[user]]
### 08 event.journal_new_comment.my_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> my journal
### 09 event.journal_new_comment.my_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> my journal
    return BML::ml(
        $key,
        {
            user      => $user,
            entryurl  => $entryurl,
            entrydesc => $entrydesc,
        }
    ) if $arg2 == 0;

    my $posteru = $comment->poster;
    my $posteruser;

    my $threadurl   = $comment->url;
    my $thread_desc = $comment->subject_text;
    if ($thread_desc) {
        $thread_desc = "\"$thread_desc\"";
        $key .= '.titled_thread';
    }
    else {
        $thread_desc = "the thread";
        $key .= '.untitled_thread';
    }

    if ($posteru) {
        if ($journal_is_owner) {
            $posteruser = LJ::ljuser($posteru);
            $key .= '.me';
        }
        else {
            $posteruser = LJ::ljuser($posteru);
            $key .= '.user';
        }
    }
    else {
        $posteruser = "(Anonymous)";
        $key .= '.anonymous';
    }
### 10 ... 33
    return BML::ml(
        $key,
        {
            user        => $user,
            threadurl   => $threadurl,
            thread_desc => $thread_desc,
            posteruser  => $posteruser,
            entryurl    => $entryurl,
            entrydesc   => $entrydesc,
        }
    );
}

sub matches_filter {
    my ( $self, $subscr ) = @_;

    return 0 unless $subscr->available_for_user;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->userid;

    # if subscription is for a specific journal (not a wildcard like 0
    # for all friends) then it must match the event's journal exactly.
    return 0 if $sjid && $sjid != $ejid;

    my ( $earg1, $earg2 ) = ( $self->arg1,   $self->arg2 );
    my ( $sarg1, $sarg2 ) = ( $subscr->arg1, $subscr->arg2 );

    my $comment = $self->comment;
    my $entry   = $comment->entry;

    my $watcher = $subscr->owner;
    return 0 unless $comment->visible_to($watcher);

    if ($watcher) {

        # not a match if this user posted the comment
        return 0 if $watcher->equals( $comment->poster );

        # not a match if opt_noemail applies
        return 0 if $self->apply_noemail( $watcher, $comment, $subscr->method );
    }

    # watching a specific journal
    if ( $sarg1 == 0 && $sarg2 == 0 ) {

        # TODO: friend group filtering in case of $sjid == 0 when
        # a subprop is filtering on a friend group
        return 1;
    }

    my $wanted_ditemid = $sarg1;

    # a (journal, dtalkid) pair identifies a comment uniquely, as does
    # a (journal, ditemid, dtalkid pair). So ditemid is optional. If we have
    # it, though, it needs to be correct.
    return 0 if $wanted_ditemid && $entry->ditemid != $wanted_ditemid;

    # watching a post
    return 1 if $sarg2 == 0;

    # watching a thread
    my $wanted_jtalkid = $sarg2;
    while ($comment) {
        return 1 if $comment->jtalkid == $wanted_jtalkid;
        $comment = $comment->parent;
    }
    return 0;
}

sub apply_noemail {
    my ( $self, $watcher, $comment, $method ) = @_;

    my $entry = $comment->entry;

    # not a match if this user posted the entry and they don't want comments emailed,
    # unless it is a reply to one of their comments or they posted the comment
    my $reply_to_own_comment = $comment->parent ? $watcher->equals( $comment->parent->poster ) : 0;
    my $receive_own_comment = $comment->posterid == $watcher->id    # we posted
        && $watcher->prop('opt_getselfemail') && $watcher->can_get_self_email;

    if (
        $watcher->equals( $entry->poster )
        && !( $reply_to_own_comment || $receive_own_comment )       # special-cased
        )
    {
        return 1 if $entry->prop('opt_noemail') && $method =~ /Email$/;
    }
}

sub jtalkid {
    my $self = shift;
    return $self->arg1;
}

# when was this comment posted or edited?
sub eventtime_unix {
    my $self = shift;
    my $cmt  = $self->comment;

    my $time = $cmt->is_edited ? $cmt->edit_time : $cmt->unixtime;
    return $cmt ? $time : $self->SUPER::eventtime_unix;
}

sub comment {
    my $self = shift;
    return LJ::Comment->new( $self->event_journal, jtalkid => $self->jtalkid );
}

sub available_for_user {
    my ( $class, $u, $subscr ) = @_;

    my $journal = $subscr->journal;

    my ( $sarg1, $sarg2 ) = ( $subscr->arg1, $subscr->arg2 );

    # not allowed to track replies to comments
    return 0
        if !$u->can_track_thread && $sarg2;

    return 0
        if ( $sarg1 == 0 && $sarg2 == 0 )
        && $journal
        && $journal->is_community
        && !$u->can_track_all_community_comments($journal);

    return 1;
}

# return detailed data for XMLRPC::getinbox
sub raw_info {
    my ( $self, $target, $flags ) = @_;
    my $extended = ( $flags and $flags->{extended} ) ? 1 : 0;    # add comments body

    my $res = $self->SUPER::raw_info;

    my $comment = $self->comment;
    my $journal = $self->u;

    $res->{journal} = $journal->user;

    return { %$res, action => 'deleted' }
        unless $comment && $comment->valid && !$comment->is_deleted;

    my $entry = $comment->entry;
    return { %$res, action => 'comment_deleted' }
        unless $entry && $entry->valid;

    return { %$res, visibility => 'no' } unless $comment->visible_to($target);

    $res->{entry}   = $entry->url;
    $res->{comment} = $comment->url;
    $res->{poster}  = $comment->poster->user if $comment->poster;
    $res->{subject} = $comment->subject_text;

    if ($extended) {
        $res->{extended}->{subject_raw} = $comment->subject_raw;
        $res->{extended}->{body}        = $comment->body_raw;
        $res->{extended}->{dtalkid}     = $comment->dtalkid;
    }

    if ( $comment->is_edited ) {
        return { %$res, action => 'edited' };
    }
    else {
        return { %$res, action => 'new' };
    }
}

1;
