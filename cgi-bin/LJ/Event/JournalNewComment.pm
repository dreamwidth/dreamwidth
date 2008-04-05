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

sub as_email_from_name {
    my ($self, $u) = @_;

    if($self->comment->poster) {
        return sprintf "%s - $LJ::SITENAMEABBREV Comment", $self->comment->poster->display_username;
    } else {
        return "$LJ::SITENAMESHORT Comment";
    }
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

    my $filename = $self->template_file_for(section => 'subject', lang => $u->prop('browselang'));
    if ($filename) {
        # Load template file into template processor
        my $t = LJ::HTML::Template->new(filename => $filename);
        $t->param(subject => $self->comment->subject_html);
        return $t->output;
    }

    if ($self->comment->subject_orig) {
        return LJ::strip_html($self->comment->subject_orig);
    } elsif ($self->comment->parent) {
        if ($edited) {
            return LJ::u_equals($self->comment->parent->poster, $u) ? 'Edited reply to your comment...' : 'Edited reply to a comment...';
        } else {
            return LJ::u_equals($self->comment->parent->poster, $u) ? 'Reply to your comment...' : 'Reply to a comment...';
        }
    } elsif (LJ::u_equals($self->comment->poster, $u)) {
        return $edited ? 'Comment you edited...' : 'Comment you posted....';
    } else {
        if ($edited) {
            return LJ::u_equals($self->comment->entry->poster, $u) ? 'Edited reply to your entry...' : 'Edited reply to an entry...';
        } else {
            return LJ::u_equals($self->comment->entry->poster, $u) ? 'Reply to your entry...' : 'Reply to an entry...';
        }
    }
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

sub content {
    my ($self, $target) = @_;

    my $comment = $self->comment;

    return undef unless $comment && $comment->valid;
    return undef unless $comment->entry && $comment->entry->valid;
    return undef unless $comment->visible_to($target);
    return undef if $comment->is_deleted;

    LJ::need_res('js/commentmanage.js');

    my $comment_body = $comment->body_html;
    my $buttons = $comment->manage_buttons;
    my $dtalkid = $comment->dtalkid;

    $comment_body =~ s/\n/<br \/>/g;

    my $ret = qq {
        <div id="ljcmt$dtalkid" class="JournalNewComment">
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

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journal = $subscr->journal;

    if (!$journal) {
        return "Someone comments in any journal on my friends page";
    }

    my $user = LJ::u_equals($journal, $subscr->owner) ? 'my journal' : LJ::ljuser($journal);

    if ($arg1 == 0 && $arg2 == 0) {
        return "Someone comments in $user, on any entry";
    }

    # load ditemid from jtalkid if no ditemid
    my $comment;
    if ($arg2) {
        $comment = LJ::Comment->new($journal, jtalkid => $arg2);
        return "(Invalid comment)" unless $comment && $comment->valid;
        $arg1 = $comment->entry->ditemid unless $arg1;
    }

    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);

    my $entry = LJ::Entry->new($journal, ditemid => $arg1);
    return "Someone comments on a deleted entry in $user" unless $entry && $entry->valid;

    my $entrydesc = $entry->subject_text;
    $entrydesc = $entrydesc ? "\"$entrydesc\"" : "an entry";

    my $entryurl  = $entry->url;
    my $in_journal = $journal_is_owner ? " on my journal" : "in $user";
    return "Someone comments on <a href='$entryurl'>$entrydesc</a> $in_journal" if $arg2 == 0;

    my $threadurl = $comment->url;

    my $posteru = $comment->poster;
    my $posteruser = $posteru ? LJ::ljuser($posteru) : "(Anonymous)";

    $posteruser = $journal_is_owner ? 'me' : $posteruser;

    my $thread_desc = $comment->subject_text ? '"' . $comment->subject_text . '"' : "the thread";

    return "Someone comments under <a href='$threadurl'>$thread_desc</a> by $posteruser in <a href='$entryurl'>$entrydesc</a> $in_journal";
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

1;
