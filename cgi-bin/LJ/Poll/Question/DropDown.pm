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

package LJ::Poll::Question::DropDown;
use strict;
use parent qw/LJ::Poll::Question::MultiChoice/;
sub previewing_snippet {
    my $self = shift;
    my $ret = '';

    my $type = $self->type;
    my $opts = $self->opts;
    #############
             my @optlist = ('', '');
            foreach my $it ($self->items) {
                LJ::Poll->clean_poll(\$it->{item});
                  push @optlist, ('', $it->{item});
              }
            $ret .= LJ::html_select({}, @optlist);

    ###########
    return $ret;
}

sub boxtype{undef}

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
        $ret .= "<div style='margin: 10px 0 10px 40px' class='poll-response'>";

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


            ### Load the answers:
            $sth = $poll->journal->prepare( "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?" );
            $sth->execute( $pollid, $qid, $poll->journalid );
            while (my ($val) = $sth->fetchrow_array) {
                $usersvoted++;
                $itvotes{$_}++;
            }
            for (values %itvotes) {
                $maxitvotes = $_ if ($_ > $maxitvotes);
            }
        }

        my $prevanswer;

        #### now, questions with items
        my @items = $poll->question($qid)->items;
        @items = map { [$_->{pollitid}, $_->{item}] } @items;

        if ($do_form) {
            my @optlist = ('', '');
            foreach my $it ($poll->question($qid)->items) {
                my $itid  = $it->{pollitid};
                my $item  = $it->{item};
                LJ::Poll->clean_poll(\$item);
                push @optlist, ($itid, $item);
            }
            $prevanswer = $clearanswers ? 0 : $preval{$qid};
            $ret .= LJ::html_select({ 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                    'selected' => $prevanswer }, @optlist);
        } else {

         foreach my $item (@items) {
            # note: itid can be fake
            my ($itid, $item) = @$item;

            LJ::Poll->clean_poll(\$item);

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