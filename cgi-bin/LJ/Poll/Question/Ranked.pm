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


# ALTER TABLE pollquestion2 CHANGE COLUMN type type enum('check','radio','drop','text','scale', 'ranked');


package LJ::Poll::Question::Ranked;
use strict;
use base qw/ LJ::Poll::Question::MultiChoice /;

our @needed_resources = qw#js/jquery/jquery-1.8.3.js
                         js/jquery/jquery.ui.core.js
                         js/jquery/jquery.ui.widget.js
                         js/jquery/jquery.ui.mouse.js
                         js/jquery/jquery.ui.sortable.js
                         stc/css/components/rankedpoll.css
                         js/jquery.rankedpoll.js
                        #;


sub translate_individual_answer {
    my ($self, $value, $items) = @_;
    my %h = rankings_string_to_hash($value);
    return join(", ", map { $items->{$_} } sort {$h{$a} <=> $h{$b}} keys %h );
}

# sub process_tag_options {
#     my ($opts, $qopts,$err) = @_;
#     return $qopts;
# }

sub is_valid_answer {
    #updated
    my ($self, $val) = @_;

    if (length($val) > 0) { # if the user answered to this question
        my @opts = split( /,/ , $val );
        my $num_opts = scalar @opts;  # returns the number of options they ranked
        my $num_items = scalar $self->items;

        my (%seen_q,%seen_r, %ranks);
        for (@opts){
            unless ( /^(\d+)=(\d*)$/ ){ return("error: Malformed ranking",2); }
            my ( $qn, $rank ) = ($1, $2);
            if ( $qn > $num_items ){ return("error: Question number too high",3); }
            if ( $seen_q{$qn}++ ){ return("error: Question $qn ranked more than once",5); }
            if ( not(defined $rank) || $rank eq ''){next}
            if ( $rank < 1 ){ return("error: Highest ranking allowed is 1",4); }
            if ( $seen_r{$rank}++ ){ return("error: Rank $rank assigned more than once",6); }
        }

     }
    return 1; 
}


sub rankings_string_to_hash {
     my ($string) = @_;
     my %hash;
     for (split(/,/, $string)){
         if(/^(\d+)=(\d+)$/){$hash{$1} = $2}
     }    
     return %hash;
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
 
        LJ::need_res( @needed_resources );
        my $text = $self->text;
        LJ::Poll->clean_poll(\$text);
        $ret .= "<div class='poll-inquiry'><p>$text</p>";

        $ret .= "<div style='margin: 10px 0 10px 40px' class='poll-response'>";

        my $usersvoted = 0;
        my %itvotes;
        my $maxitvotes = 1;
        my @result_of_runoff;
        
        
         my (@injs, @outjs);
        if ($mode eq "results") {
            ### to see individual's answers
            my $posterid = $poll->posterid;
            $ret .= qq {
                <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;qid=$qid&amp;mode=ans'
                     class='LJ_PollAnswerLink' lj_pollid='$pollid' lj_qid='$qid' lj_posterid='$posterid' lj_page='0' lj_pagesize="$pagesize"
                     id="LJ_PollAnswerLink_${pollid}_$qid">
                } . LJ::Lang::ml('poll.viewanswers') . "</a><br />" if $poll->can_view;

            $sth = $poll->journal->prepare( "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?" );
            $sth->execute( $pollid, $qid, $poll->journalid );
            my @votes;
            while (my ($val) = $sth->fetchrow_array) {
                $usersvoted++;
                my %h = rankings_string_to_hash($val);
 
                push @votes, \%h;
 
            }
            my ($winners, $ar) = do_runoff(@votes);
            @result_of_runoff = @$ar;
            %itvotes = %{$result_of_runoff[-1]}; # final round results. 
            for (values %itvotes) {
                $maxitvotes = $_ if ($_ > $maxitvotes);
            }
            my $num_of_rounds = scalar (@result_of_runoff);
            if ($num_of_rounds > 1){
                $ret .= "Status in last round of elimination ($num_of_rounds of $num_of_rounds): <br />"; 
            } else {
                $ret .= "No elimination necessary - showing first choices <br />";
            }
        }

        my @items = $poll->question($qid)->items;
        @items = map { [$_->{pollitid}, $_->{item}] } @items;
        my $qvalue = $preval{$qid} || '';
        my %my_votes = rankings_string_to_hash($qvalue);

        for my $item (@items) {
            # note: itid can be fake
            my ($itid, $item) = @$item;

            LJ::Poll->clean_poll(\$item);

            # displaying a per-item numberbox
            if ($do_form) {
                
                
                my $js_snippet .= qq{<li class="ui-state-default" id="rankedpoll_item-$pollid+$qid-$itid">$item</li>};

                $prevanswer = $clearanswers ? '' : ($my_votes{$itid} // '');

                if ($prevanswer){
                    $injs[$prevanswer - 1] = $js_snippet;
                } else {
                    push @outjs, $js_snippet;
                }
                
                $ret .= '<div class="rankedpoll_hideable">';
                $ret .= LJ::html_text({ 'size' => 3, 'maxlength' => 3, 'class'=>"poll-$pollid",
                                    'name' => "polltuple-$qid-$itid", 'id' => "polltuple-$pollid+$qid-$itid", 'value' => $prevanswer });
                $ret .= " <label for='pollq-$pollid-$qid-$itid'>$item</label><br />";
                $ret .= '</div>';

                next;
            } else {

                # displaying results
                my $count = ( defined $itid ) ? $itvotes{$itid} || 0 : 0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);

                # did the user viewing this poll choose this option? If so, mark it
                my $answered =  $my_votes{$itid} ? "Your ranking: $my_votes{$itid}" : "";

                $ret .= "<p>$item<br /><span style='white-space: nowrap'>";
                $ret .= LJ::img( 'poll_left', '', { style => 'vertical-align:middle' } );
                $ret .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle; height: 14px;' height='14' width='$width' alt='' />";
                $ret .= LJ::img( 'poll_right', '', { style => 'vertical-align:middle' } );
                $ret .= "<b>$count</b> ($percent%) $answered</span></p>";
            }

        }
            
       if ($do_form) {
  
            my $js_poll = q!<div class="rankedlistwrapper"><ul class="rankedpoll_sortable_from">Unused Options!;
            $js_poll.= join("", grep {defined $_} @outjs);
            $js_poll.= '</ul><ul class="rankedpoll_sortable_to" id="rankedpoll-'."$pollid+$qid".'">Your Choices';
            $js_poll.= join("", grep {defined $_} @injs);
            $js_poll.= '</ul></div>';
            $js_poll =~ s/\n//g;
            $ret .= q!<script type="text/javascript"> 
                    document.write('! .$js_poll. q!');
                    </script>!;

        }
        $ret .= "</div></div>";

 #####################
    return $ret;
}



sub do_runoff{
    my @votes ;
    for my $h (@_){
       push @votes, [sort {$h->{$a} <=> $h->{$b}} grep {$h->{$_}} keys %$h];
    }

    return ([],[]) unless scalar @votes;
    # no doubt this can be made more efficient but.
    my %cand;
    for my $v (@votes){
        $cand{$_} = 1 for @$v;
    }
    my @candidates = sort keys %cand;
    return ([],[]) unless scalar @candidates;

    my $round = 1;
    my @history;
    while (1){
        my %firstchoices = map {$_ => 0} @candidates;
        for my $v (@votes){
            $firstchoices{$v->[0]}++ if scalar @$v;
        }
        push @history, \%firstchoices;
        my $lowestscore  = $firstchoices{$candidates[0]};
        my $highestscore = $firstchoices{$candidates[0]};
        for my $c (@candidates){
            $lowestscore  = $firstchoices{$c} if $firstchoices{$c} < $lowestscore;
            $highestscore = $firstchoices{$c} if $firstchoices{$c} > $highestscore;
        }
        
        last if ($lowestscore == $highestscore); # winner or tie
        if ($highestscore > (scalar @votes / 2)){ # if one candidate has absolute majority
            @candidates = grep {$firstchoices{$_} == $highestscore } @candidates;
            last;
        }
        
        # Elimination stage
        @candidates = grep {$firstchoices{$_} > $lowestscore } @candidates;
        @votes = map {[grep {$firstchoices{$_} > $lowestscore } @$_]} @votes;
        $round++;
    }
    return (\@candidates, \@history); #winner or jointwinners; results at each round of elimination
}


sub decompose_votes{
    my ($self,$val) = @_; 
    my %h = rankings_string_to_hash($val);  
    return (sort {$h{$a} <=> $h{$b}} keys %h)[0]
}


1;