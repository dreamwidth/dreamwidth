# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
# #
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Poll::Question::MultiChoice;
use strict;
use base qw/LJ::Poll::Question/;

sub has_sub_items {1}

sub previewing_snippet {
    my $self = shift;
    my $ret = '';

    my $type = $self->type;
    my $opts = $self->opts;
    #############
    foreach my $it ($self->items) {
    LJ::Poll->clean_poll(\$it->{item});
        $ret .= LJ::html_check({ 'type' => $self->type }) . "$it->{item}<br />\n";
    }
    ###########
    return $ret;
}


sub translate_individual_answer {
    my ($self, $value, $items) = @_;
    return $items->{$value};
}

sub display_result {
    my ($self, $do_form, $preval, $clearanswers, $mode, $pagesize) = @_;
    my $ret = '';
    my $prevanswer;
    my %preval = %$preval;
    my $qid = $self->pollqid;
    my $pollid = $self->pollid;
    my $poll = $self->poll;
    my $sth;
 #################
        my $text = $self->text;
        LJ::Poll->clean_poll(\$text);
        $ret .= "<div class='poll-inquiry'><p>$text</p>";

        # shows how many options a user must/can choose if that restriction applies
        if ($do_form) { $ret .= $self->previewing_snippet_preamble }
        
        $ret .= "<div style='margin: 10px 0 10px 40px' class='poll-response'>";

        ### get statistics, for scale questions

        my $usersvoted = 0;
        my %itvotes;
        my $maxitvotes = 1;

        if ($mode eq "results") {
            ### to see individual's answers
            my $posterid = $poll->posterid;
            $ret .= qq {
                <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;qid=$qid&amp;mode=ans'
                     class='LJ_PollAnswerLink' lj_pollid='$pollid' lj_qid='$qid' lj_posterid='$posterid' lj_page='0' lj_pagesize="$pagesize"
                     id="LJ_PollAnswerLink_${pollid}_$qid">
                } . LJ::Lang::ml('poll.viewanswers') . "</a><br />" if $poll->can_view;

             ### but, if this is a non-text item, and we're showing results, need to load the answers:
            $sth = $poll->journal->prepare( "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?" );
            $sth->execute( $pollid, $qid, $poll->journalid );
            while (my ($val) = $sth->fetchrow_array) {
                $usersvoted++;
                for ($self->decompose_votes($val)) { #decompose_votes is subclassed
                    $itvotes{$_}++;
                }
            }

            for (values %itvotes) {
                $maxitvotes = $_ if ($_ > $maxitvotes);
            }
        }

        my @items = $poll->question($qid)->items;
        @items = map { [$_->{pollitid}, $_->{item}] } @items;

        for my $item (@items) {
            # note: itid can be fake
            my ($itid, $item) = @$item;

            LJ::Poll->clean_poll(\$item);

            # displaying a radio or checkbox
            if ($do_form) {
                my $qvalue = $preval{$qid} || '';
                $prevanswer = $clearanswers ? 0 : $qvalue =~ /\b$itid\b/;
                $ret .= LJ::html_check({ 'type' => $self->boxtype, 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                            'value' => $itid, 'id' => "pollq-$pollid-$qid-$itid",
                                            'selected' => $prevanswer });
                $ret .= " <label for='pollq-$pollid-$qid-$itid'>$item</label><br />";
                next;
            } else {

                # displaying results
                my $count = ( defined $itid ) ? $itvotes{$itid} || 0 : 0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);

                # did the user viewing this poll choose this option? If so, mark it
                my $qvalue = $preval{$qid} || '';
                my $answered = ( $qvalue =~ /\b$itid\b/ ) ? "*" : "";

                $ret .= "<p>$item<br /><span style='white-space: nowrap'>";
                $ret .= LJ::img( 'poll_left', '', { style => 'vertical-align:middle' } );
                $ret .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle; height: 14px;' height='14' width='$width' alt='' />";
                $ret .= LJ::img( 'poll_right', '', { style => 'vertical-align:middle' } );
                $ret .= "<b>$count</b> ($percent%) $answered</span></p>";
            }

        }
        $ret .= "</div></div>";

 #####################
    return $ret;
}


1;