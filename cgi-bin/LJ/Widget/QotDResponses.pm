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

package LJ::Widget::QotDResponses;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::QotD;

sub need_res {
    return qw( js/widgets/qotd.js stc/widgets/qotd.css stc/widgets/qotdresponses.css );
}

# how many individual 
sub responses_per_page { 30 }

# how much of each entry should we show?
sub entry_show_length { 200 }

sub load_responses {
    my $class = shift;
    my %opts = @_;

}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $hide_question = $opts{hide_question};

    my $remote = LJ::get_remote();

    my $get = $class->get_args;

    my $qid  = $get->{qid}+0;
    my $skip = $get->{skip}+0;

    my ($q) = $qid ? LJ::QotD->get_single_question($qid) : LJ::QotD->get_questions;
    $qid = $q->{qid} if $q;
    return $class->ml('widget.qotdresponses.no.entries.to.display') unless $qid;

    # get responses
    my $show_size = $class->responses_per_page;
    my $queue = LJ::queue("latest_qotd_$qid");
    my @responses = $queue->get($skip, $show_size+1, reverse => 1);

    # we'll try to fetch 1 more than we need... if it came back then
    # we know we need a 'more' link below.
    my $need_more = @responses >= $show_size + 1 ? 1 : 0;

    # now truncate the list back down to $show_size
    @responses = @responses[0..($show_size-1)] if @responses > $show_size;

    my $ret = "";
    unless (@responses) {
        my $answer_url = LJ::Widget::QotD->answer_url($q);

        $ret .= "<?p " . $class->ml('widget.qotdresponses.there.are.no.answers') . " p?>";
        $ret .= "<ul>";
        $ret .= "<li><a href='$answer_url'>" . $class->ml('widget.qotdresponses.answer.the.question') . "</a></li>" if $answer_url;
        $ret .= "<li><a href='" . $remote->journal_base . "/read'>" . $class->ml('widget.qotdresponses.read.your.friends.page') . "</a></li>"
            if $remote;
        $ret .= "<li><a href='$LJ::SITEROOT/site/search.bml'>" . $class->ml('widget.qotdresponses.explore') . " $LJ::SITENAMEABBREV</a></li>";
        $ret .= "</ul>";
        return $ret;
    }


    unless ($hide_question) {
       my $widget_html = LJ::Widget::QotD->render(question => $q, nocontrols => 1);

        $ret .= "<div class='qotd-container'>$widget_html</div>";
    }

    $ret .= $class->render_responses(@responses);

    # did we have more to display?
    if ($need_more) {
        my $newskip = $skip + $show_size;
        $ret .= "<div><a href='$LJ::SITEROOT/misc/latestqotd.bml?qid=$qid&skip=$newskip'>" . $class->ml('widget.qotdresponses.previous') . " $show_size</a></div>";
    }

    return $ret;
}

sub render_responses {
    my $class = shift;
    my @responses = @_;

    my $remote = LJ::get_remote();

    my $ret = "";
    
  RESPONSE:
    foreach my $resp (@responses) {
        my ($userid, $jitemid) = split(',', $resp);

        if (! $userid || ! $jitemid) {
            warn "invalid qotd queue item: '$resp'";
            next;
        }

        my $journal = LJ::load_userid($userid);
        my $entry = LJ::Entry->new($journal, jitemid => $jitemid);
        next unless $journal && $entry && $entry->valid;
        next unless $entry->visible_to($remote);

        foreach my $u (($entry->journal, $entry->poster)) {
            next RESPONSE unless $u->is_visible;
            next RESPONSE if $u->prop("exclude_from_verticals");
            next RESPONSE if $u->prop("latest_optout");
        }

        my $userpic = $entry->userpic;
        my $userpic_html = '';

        if ($userpic) {
            my $img = $userpic->imgtag(width => 75);
            $userpic_html = qq { <div class="lj_qotd_entry_userpic">$img</div> };
        }

        my $entry_html = LJ::trim($entry->event_html_summary($class->entry_show_length, { noexpandembedded => 1 }));
        my $entry_subject = $entry->subject_html;
        my $entry_url = $entry->url;
        my $entry_cmt_link = $entry->reply_url;
        my $comments = $entry->comment_text;

        $ret .= qq {
            <div class="lj_qotd_entry_container">
                $userpic_html
                <div class="lj_qotd_entry_subject">$entry_subject</div>
                <div class="lj_qotd_entry_body">$entry_html</div>
                <div>
        };    
                
        $ret .= "<a href=\"$entry_url\">" . $class->ml('widget.qotdresponses.read.more') . "</a> | <a href=\"$entry_cmt_link\">$comments</a>";
        $ret .= '</div><div class="clear">&nbsp;</div></div>';
        
    }

    return $ret;
}

1;
