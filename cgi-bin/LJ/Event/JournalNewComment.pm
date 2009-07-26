package LJ::Event::JournalNewComment;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Comment LJ::HTML::Template);
use Carp qw(croak);
use base 'LJ::Event';

# we don't allow subscriptions to comments on friends' journals, so
# setting undef on this skips some nasty queries
sub zero_journalid_subs_means { undef }

sub new {
    my ($class, $comment) = @_;
    croak 'Not an LJ::Comment' unless blessed $comment && $comment->isa("LJ::Comment");
    return $class->SUPER::new($comment->journal, $comment->jtalkid);
}

sub is_common { 1 }

my @_ml_strings_en = (
    'esn.mail_comments.fromname.user',                      # "[[user]] - [[sitenameabbrev]] Comment",
    'esn.mail_comments.fromname.anonymous',                 # "[[sitenameshort]] Comment",
    'esn.mail_comments.subject.edit_reply_to_your_comment', # "Edited reply to your comment...",
    'esn.mail_comments.subject.reply_to_your_comment',      # "Reply to your comment...",
    'esn.mail_comments.subject.edit_reply_to_your_entry',   # "Edited reply to your entry...",
    'esn.mail_comments.subject.reply_to_your_entry',        # "Reply to your entry...",
    'esn.mail_comments.subject.edit_reply_to_an_entry',     # "Edited reply to an entry...",
    'esn.mail_comments.subject.reply_to_an_entry',          # "Reply to an entry...",
    'esn.mail_comments.subject.edit_reply_to_a_comment',    # "Edited reply to a comment...",
    'esn.mail_comments.subject.reply_to_a_comment',         # "Reply to a comment...",
    'esn.mail_comments.subject.comment_you_posted',         # "Comment you posted...",
    'esn.mail_comments.subject.comment_you_edited',         # "Comment you edited...",
);

sub as_email_from_name {
    my ($self, $u) = @_;

    my $lang = $u->prop('browselang');

    my $vars = {
        user            => $self->comment->poster ? $self->comment->poster->display_username : '',
        sitenameabbrev  => $LJ::SITENAMEABBREV,
        sitenameshort   => $LJ::SITENAMESHORT,
    };

    my $key = 'esn.mail_comments.fromname.';
    if($self->comment->poster) {
        $key .= 'user';
    } else {
        $key .= 'anonymous';
    }

    return LJ::Lang::get_text($lang, $key, undef, $vars);
}

sub as_email_headers {
    my ($self, $u) = @_;

    my $this_msgid = $self->comment->email_messageid;
    my $top_msgid = $self->comment->entry->email_messageid;

    my $par_msgid;
    if ($self->comment->parent) { # a reply to a comment
        $par_msgid = $self->comment->parent->email_messageid;
    } else { # reply to an entry
        $par_msgid = $top_msgid;
        $top_msgid = "";  # so it's not duplicated
    }

    my $journalu = $self->comment->entry->journal;
    my $headers = {
        'Message-ID'   => $this_msgid,
        'In-Reply-To'  => $par_msgid,
        'References'   => "$top_msgid $par_msgid",
        'X-LJ-Journal' => $journalu->user,
    };

    return $headers;

}

sub as_email_subject {
    my ($self, $u) = @_;

    my $edited = $self->comment->is_edited;
    my $lang = $u->prop('browselang');

    my $filename = $self->template_file_for(section => 'subject', lang => $lang);
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);
        $t->param(subject => $self->comment->subject_html);
        return $t->output;
    }

    my $key = 'esn.mail_comments.subject.';
    if ($self->comment->subject_orig) {
        return LJ::strip_html($self->comment->subject_orig);
    } elsif (LJ::u_equals($self->comment->poster, $u)) {
        $key .= $edited ? 'comment_you_edited' : 'comment_you_posted';
    } elsif ($self->comment->parent) {
        if ($edited) {
            $key .= LJ::u_equals($self->comment->parent->poster, $u) ? 'edit_reply_to_your_comment' : 'edit_reply_to_a_comment';
        } else {
            $key .= LJ::u_equals($self->comment->parent->poster, $u) ? 'reply_to_your_comment' : 'reply_to_a_comment';
        }
    } else {
        if ($edited) {
            $key .= LJ::u_equals($self->comment->entry->poster, $u) ? 'edit_reply_to_your_entry' : 'edit_reply_to_an_entry';
        } else {
            $key .= LJ::u_equals($self->comment->entry->poster, $u) ? 'reply_to_your_entry' : 'reply_to_an_entry';
        }
    }
    return LJ::Lang::get_text($lang, $key);
}

sub as_email_string {
    my ($self, $u) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    my $filename = $self->template_file_for(section => 'body_text', lang => $u->prop('browselang'));
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);

        return $comment->format_template_text_mail($u, $t) if $t;
    }

    return $comment->format_text_mail($u);
}

sub as_email_html {
    my ($self, $u) = @_;
    my $comment = $self->comment or return "(Invalid comment)";

    my $filename = $self->template_file_for(section => 'body_html', lang => $u->prop('browselang'));
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);

        return $comment->format_template_html_mail($u, $t) if $t;
    }
 
    return $comment->format_html_mail($u);
}

sub as_string {
    my ($self, $u) = @_;
    my $comment = $self->comment;
    my $journal = $comment->entry->journal->user;

    return "There is a new anonymous comment in $journal at " . $comment->url
        unless $comment->poster;

    my $poster = $comment->poster->display_username;
    if ($self->comment->is_edited) {
        return "$poster has edited a comment in $journal at " . $comment->url;
    } else {
        return "$poster has posted a new comment in $journal at " . $comment->url;
    }
}

sub as_sms {
    my ($self, $u) = @_;

    my $user = $self->comment->poster ? $self->comment->poster->display_username : '(Anonymous user)';
    my $edited = $self->comment->is_edited;

    my $msg;

    if ($self->comment->parent) {
        if ($edited) {
            $msg = LJ::u_equals($self->comment->parent->poster, $u) ? "$user edited a reply to your comment: " : "$user edited a reply to a comment: ";
        } else {
            $msg = LJ::u_equals($self->comment->parent->poster, $u) ? "$user replied to your comment: " : "$user replied to a comment: ";
        }
    } else {
        if ($edited) {
            $msg = LJ::u_equals($self->comment->entry->poster, $u) ? "$user edited a reply to your post: " : "$user edited a reply to a post: ";
        } else {
            $msg = LJ::u_equals($self->comment->entry->poster, $u) ? "$user replied to your post: " : "$user replied to a post: ";
        }
    }

    return $msg . $self->comment->body_text;
}

sub _can_view_content {
    my ( $self, $comment, $target ) = @_;

    return undef unless $comment && $comment->valid;
    return undef unless $comment->entry && $comment->entry->valid;
    return undef unless $comment->visible_to( $target );
    return undef if $comment->is_deleted;

    return 1;
}
sub content {
    my ($self, $target) = @_;

    my $comment = $self->comment;
    return undef unless $self->_can_view_content( $comment, $target );

    LJ::need_res('js/commentmanage.js');

    my $comment_body = $comment->body_html;
    my $buttons = $comment->manage_buttons;
    my $dtalkid = $comment->dtalkid;
    my $htmlid  = LJ::Talk::comment_htmlid( $dtalkid );

    $comment_body =~ s/\n/<br \/>/g;

    my $ret = qq {
        <div id="$htmlid" class="JournalNewComment">
            <div class="ManageButtons">$buttons</div>
            <div class="Body">$comment_body</div>
        </div>
    };

    my $cmt_info = $comment->info;
    my $cmt_info_js = LJ::js_dumper($cmt_info) || '{}';

    my $posterusername = $self->comment->poster ? $self->comment->poster->{user} : "";

    $ret .= qq {
        <script language="JavaScript">
        };

    while (my ($k, $v) = each %$cmt_info) {
        $k = LJ::ejs($k);
        $v = LJ::ejs($v);
        $ret .= "LJ_cmtinfo['$k'] = '$v';\n";
    }

    my $dtid_cmt_info = {u => $posterusername, rc => []};

    $ret .= "LJ_cmtinfo['$dtalkid'] = " . LJ::js_dumper($dtid_cmt_info) . "\n";

    $ret .= qq {
        </script>
        };
    $ret .= $self->as_html_actions;

    return $ret;
}

sub content_summary {
    my ( $self, $target ) = @_;

    my $comment = $self->comment;
    return undef unless $self->_can_view_content( $comment, $target );

    my $body_summary = $comment->body_html_summary( 300 );
    my $ret = $body_summary;
    $ret .= "..." if $comment->body_html ne $body_summary;
    $ret .= $self->as_html_actions;

    return $ret;
}

sub as_html {
    my ($self, $target) = @_;

    my $comment = $self->comment;
    my $journal = $self->u;

    return sprintf("(Deleted comment in %s)", $journal->ljuser_display)
        unless $comment && $comment->valid && !$comment->is_deleted;

    my $entry = $comment->entry;
    return sprintf("(Comment on a deleted entry in %s)", $journal->ljuser_display)
        unless $entry && $entry->valid;

    return "(You are not authorized to view this comment)" unless $comment->visible_to($target);

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($comment->poster);
    my $url = $comment->url;

    my $in_text = '<a href="' . $entry->url . '">an entry</a>';
    my $subject = $comment->subject_text ? ' "' . $comment->subject_text . '"' : '';

    my $poster = $comment->poster ? "by $pu" : '';
    if ($comment->is_edited) {
        return "Edited <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";
    } else {
        return "New <a href=\"$url\">comment</a> $subject $poster on $in_text in $ju.";
    }
}

sub as_html_actions {
    my ($self) = @_;

    my $comment = $self->comment;
    my $url = $comment->url;
    my $reply_url = $comment->reply_url;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$reply_url'>Reply</a>";
    $ret .= " <a href='$url'>Link</a>";
    $ret .= "</div>";

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
    my ($class, $subscr) = @_;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journal = $subscr->journal;

    my $key = 'event.journal_new_comment';

    if (!$journal) {
### 01 event.journal_new_comment.friend=Someone comments in any journal on my friends page
        return BML::ml($key . '.friend');
    }

    my ($user, $journal_is_owner);
    if (LJ::u_equals($journal, $subscr->owner)) {
        $user = 'my journal';
        $key .= '.my_journal';
        my $journal_is_owner = 1;
    } else {
        $user = LJ::ljuser($journal);
        $key .= '.user_journal';
        my $journal_is_owner = 0;
    }

    if ($arg1 == 0 && $arg2 == 0) {
### 02 event.journal_new_comment.my_journal=Someone comments in my journal, on any entry
### 03 event.journal_new_comment.user_journal=Someone comments in [[user]], on any entry
        return BML::ml($key, { user => $user });
    }

    # load ditemid from jtalkid if no ditemid
    my $comment;
    if ($arg2) {
        $comment = LJ::Comment->new($journal, jtalkid => $arg2);
        return "(Invalid comment)" unless $comment && $comment->valid;
        $arg1 = $comment->entry->ditemid unless $arg1;
    }

    my $entry = LJ::Entry->new($journal, ditemid => $arg1);
### 04 event.journal_new_comment.user_journal.deleted=Someone comments on a deleted entry in [[user]]
### 05 event.journal_new_comment.my_journal.deleted=Someone comments on a deleted entry in my journal
    return BML::ml($key . '.deleted', { user => $user }) unless $entry && $entry->valid;

    my $entrydesc = $entry->subject_text;
    if ($entrydesc) {
        $entrydesc = "\"$entrydesc\"";
        $key .= '.titled_entry';
    } else {
        $entrydesc = "an entry";
        $key .= '.untitled_entry';
    }

    my $entryurl  = $entry->url;
### 06 event.journal_new_comment.user_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> in [[user]]
### 07 event.journal_new_comment.user_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> in [[user]]
### 08 event.journal_new_comment.my_journal.titled_entry=Someone comments on <a href='[[entryurl]]'>[[entrydesc]]</a> my journal
### 09 event.journal_new_comment.my_journal.untitled_entry=Someone comments on <a href='[[entryurl]]'>en entry</a> my journal
    return BML::ml($key,
        {
            user        => $user,
            entryurl    => $entryurl,
            entrydesc   => $entrydesc,
        }) if $arg2 == 0;

    my $posteru = $comment->poster;
    my $posteruser;

    my $threadurl = $comment->url;
    my $thread_desc = $comment->subject_text;
    if ($thread_desc) {
        $thread_desc = "\"$thread_desc\"";
        $key .= '.titled_thread';
    } else {
        $thread_desc = "the thread";
        $key .= '.untitled_thread';
    }

    if ($posteru) {
        if ($journal_is_owner) {
            $posteruser = LJ::ljuser($posteru);
            $key .= '.me';
        } else {
            $posteruser = LJ::ljuser($posteru);
            $key .= '.user';
        }
    } else {
        $posteruser = "(Anonymous)";
        $key .= '.anonymous';
    }
### 10 ... 33
    return BML::ml($key,
    {
        user            => $user,
        threadurl       => $threadurl,
        thread_desc     => $thread_desc,
        posteruser      => $posteruser,
        entryurl        => $entryurl,
        entrydesc       => $entrydesc,
    });
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};

    # if subscription is for a specific journal (not a wildcard like 0
    # for all friends) then it must match the event's journal exactly.
    return 0 if $sjid && $sjid != $ejid;

    my ($earg1, $earg2) = ($self->arg1, $self->arg2);
    my ($sarg1, $sarg2) = ($subscr->arg1, $subscr->arg2);

    my $comment = $self->comment;
    my $entry   = $comment->entry;

    my $watcher = $subscr->owner;
    return 0 unless $comment->visible_to($watcher);

    # not a match if this user posted the comment and they don't
    # want to be notified of their own posts
    if (LJ::u_equals($comment->poster, $watcher)) {
        return 0 unless $watcher->get_cap('getselfemail') && $watcher->prop('opt_getselfemail');
    }

    # not a match if this user posted the entry and they don't want comments emailed,
    # unless they posted it. (don't need to check again for the cap, since we did above.)
    if (LJ::u_equals($entry->poster, $watcher) && !$watcher->prop('opt_getselfemail')) {
        return 0 if $entry->prop('opt_noemail') && $subscr->method =~ /Email$/;
    }

    # watching a specific journal
    if ($sarg1 == 0 && $sarg2 == 0) {
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

sub jtalkid {
    my $self = shift;
    return $self->arg1;
}

# when was this comment posted or edited?
sub eventtime_unix {
    my $self = shift;
    my $cmt = $self->comment;

    my $time = $cmt->is_edited ? $cmt->edit_time : $cmt->unixtime;
    return $cmt ? $time : $self->SUPER::eventtime_unix;
}

sub comment {
    my $self = shift;
    return LJ::Comment->new($self->event_journal, jtalkid => $self->jtalkid);
}

sub available_for_user  {
    my ($class, $u, $subscr) = @_;

    # not allowed to track replies to comments
    return 0 if ! $u->get_cap('track_thread') &&
        $subscr->arg2;

    return 1;
}

# return detailed data for XMLRPC::getinbox
sub raw_info {
    my ($self, $target, $flags) = @_;
    my $extended = ($flags and $flags->{extended}) ? 1 : 0; # add comments body
    
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

    if ($extended){
        $res->{extended}->{subject_raw} = $comment->subject_raw;
        $res->{extended}->{body}        = $comment->body_raw;
        $res->{extended}->{dtalkid}     = $comment->dtalkid;
    }

    if ($comment->is_edited) {
        return { %$res, action => 'edited' };
    } else {
        return { %$res, action => 'new' };
    }
}

1;
