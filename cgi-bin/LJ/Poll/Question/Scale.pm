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

package LJ::Poll::Question::Scale;
use strict;
use parent qw/LJ::Poll::Question/;
sub has_sub_items {0}
sub process_tag_options {
    my ($opts, $qopts, $err) = @_;
    my $from = 1;
    my $to = 10;
    my $by = 1;
    my $lowlabel = "";
    my $highlabel = "";

    if (defined $opts->{'from'}) {
        $from = int($opts->{'from'});
    }
    if (defined $opts->{'to'}) {
        $to = int($opts->{'to'});
    }
    if (defined $opts->{'by'}) {
        $by = int($opts->{'by'});
    }
    if ( defined $opts->{'lowlabel'} ) {
        $lowlabel = LJ::strip_html( $opts->{'lowlabel'} );
    }
    if ( defined $opts->{'highlabel'} ) {
        $highlabel = LJ::strip_html( $opts->{'highlabel'} );
    }
    if ($by < 1) {
        return $err->('poll.error.scaleincrement');
    }
    if ($from >= $to) {
        return $err->('poll.error.scalelessto');
    }
    my $scaleoptions = ( ( $to - $from ) / $by ) + 1;
    if ( $scaleoptions > 21 ) {
        return $err->( 'poll.error.scaletoobig1', { 'maxselections' => 21, 'selections' => $scaleoptions - 21 } );
    }
    $qopts->{'opts'} = "$from/$to/$by/$lowlabel/$highlabel";
    return $qopts;
}

sub previewing_snippet {
    my $self = shift;
    my $ret = '';

    my $type = $self->type;
    my $opts = $self->opts;
    #############
       my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $opts );
        $by ||= 1;
        my $count = int(($to-$from)/$by) + 1;
        my $do_radios = ($count <= 11);

        # few opts, display radios
        if ($do_radios) {
            $ret .= "<table summary=''><tr valign='top' align='center'>\n";
            $ret .= "<td style='padding-right: 5px;'><b>$lowlabel</b></td>";
            for (my $at = $from; $at <= $to; $at += $by) {
                $ret .= "<td>" . LJ::html_check({ 'type' => 'radio' }) . "<br />$at</td>\n";
            }
            $ret .= "<td style='padding-left: 5px;'><b>$highlabel</b></td>";
            $ret .= "</tr></table>\n";

            # many opts, display select
        } else {
            my @optlist = ( '', ' ' );
            push @optlist, ( $from, $from . " " . $lowlabel );

            my $at = 0;
            for ( $at=$from+$by; $at<=$to-$by; $at+=$by ) {
                push @optlist, ('', $at);
            }

            push @optlist, ( $at, $at . " " . $highlabel );

            $ret .= LJ::html_select({}, @optlist);
        }

    ###########
    return $ret;
}

sub get_summary_stats{
    my $self = shift;
    my $pollid = $self->poll->pollid;
    my $qid = $self->pollqid;
    my $journalid = $self->poll->journalid;
    my $sth = $self->poll->journal->prepare( "SELECT COUNT(*), AVG(value), STDDEV(value) FROM pollresult2 " .
                                    "WHERE pollid=? AND pollqid=? AND journalid=?" );
    $sth->execute( $pollid, $qid, $journalid );

    my ( $valcount, $valmean, $valstddev ) = $sth->fetchrow_array;

    # find median:
    my $valmedian = 0;
    if ($valcount == 1) {
        $valmedian = $valmean;
    } elsif ($valcount > 1) {
        my ($mid, $fetch);
        # fetch two mids and average if even count, else grab absolute middle
        $fetch = ($valcount % 2) ? 1 : 2;
        $mid = int(($valcount+1)/2);
        my $skip = $mid-1;

        $sth = $self->journal->prepare(
            "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=? " .
            "ORDER BY value+0 LIMIT $skip,$fetch" );
        $sth->execute( $pollid, $qid, $journalid );

        while (my ($v) = $sth->fetchrow_array) {
            $valmedian += $v;
        }
        $valmedian /= $fetch;
    }
    return ($valcount, $valmean, $valstddev, $valmedian);
}

sub is_valid_answer {
    my ($self, $val) = @_;
    my $opts = $self->opts;
    my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $opts );
    if ($val < $from || $val > $to) {
        # bogus! cheating?
        return 0;
    }
    return 1; 
}


sub previewing_snippet_preamble {
    my $self = shift;
    my $opts = $self->opts;
    my ( $mincheck, $maxcheck ) = split( m!/!, $opts );
    my $ret = '';
    $mincheck ||= 0;
    $maxcheck ||= 255;

    if ($mincheck > 0 && $mincheck eq $maxcheck ) {
        $ret .= "<i>". LJ::Lang::ml( "poll.checkexact2", { options => $mincheck } ). "</i><br />\n";
    }
    else {
        if ($mincheck > 0) {
            $ret .= "<i>". LJ::Lang::ml( "poll.checkmin2", { options => $mincheck } ). "</i><br />\n";
        }

        if ($maxcheck < 255) {
            $ret .= "<i>". LJ::Lang::ml( "poll.checkmax2", { options => $maxcheck } ). "</i><br />\n";
        }
    }
    return $ret;
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
        $ret .= "<div style='margin: 10px 0 10px 40px' class='poll-response'>";

        my ($valcount, $valmean, $valstddev, $valmedian) = $self->get_summary_stats;

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

            ### if this is a text question and the viewing user answered it, show that answer
            if ( $self->type ne "text" ) {
                ### but, if this is a non-text item, and we're showing results, need to load the answers:
                $sth = $poll->journal->prepare( "SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?" );
                $sth->execute( $pollid, $qid, $poll->journalid );
                while (my ($val) = $sth->fetchrow_array) {
                    $usersvoted++;
                    $itvotes{$val}++;
                }

                for (values %itvotes) {
                    $maxitvotes = $_ if ($_ > $maxitvotes);
                }
            }
        }

        my $prevanswer;

        if ($do_form) {
            #### scales (from 1-10) questions
            my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $self->opts );
            $by ||= 1;
            my $count = int(($to-$from)/$by) + 1;
            my $do_radios = ($count <= 11);

            # few opts, display radios
            if ($do_radios) {

                $ret .= "<table summary=''><tr valign='top' align='center'>";

                # appends the lower end
                $ret .= "<td style='padding-right: 5px;'><b>$lowlabel</b></td>" if defined $lowlabel;

                for (my $at=$from; $at<=$to; $at+=$by) {

                    my $selectedanswer = !$clearanswers && ( defined $preval{$qid} && $at == $preval{$qid});
                    $ret .= "<td style='text-align: center;'>";
                    $ret .= LJ::html_check( { 'type' => 'radio', 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                             'value' => $at, 'id' => "pollq-$pollid-$qid-$at",
                                             'selected' => $selectedanswer } );
                    $ret .= "<br /><label for='pollq-$pollid-$qid-$at'>$at</label></td>";
                }

                # appends the higher end
                $ret .= "<td style='padding-left: 5px;'><b>$highlabel</b></td>" if defined $highlabel;

                $ret .= "</tr></table>\n";

            # many opts, display select
            # but only if displaying form
            } else { #if not $do_radios...
                $prevanswer = $clearanswers ? "" : $preval{$qid};

                my @optlist = ('', '');
                push @optlist, ( $from, $from . " " . $lowlabel );

                my $at = 0;
                for ( $at=$from+$by; $at<=$to-$by; $at+=$by ) {
                    push @optlist, ($at, $at);
                }

                push @optlist, ( $at, $at . " " . $highlabel );

                $ret .= LJ::html_select({ 'name' => "pollq-$qid", 'class'=>"poll-$pollid", 'selected' => $prevanswer }, @optlist);
            }

        } else { #if not $do_form...

            my $stddev = sprintf("%.2f", $valstddev);
            my $mean = sprintf("%.2f", $valmean);
            $ret .= LJ::Lang::ml('poll.scaleanswers', { 'mean' => $mean, 'median' => $valmedian, 'stddev' => $stddev });
            $ret .= "<br />\n";
            $ret .= "<table summary=''>";

            my @items = $poll->question($qid)->items;
            @items = map { [$_->{pollitid}, $_->{item}] } @items;

            # generate poll items dynamically since this is a scale

            my ( $from, $to, $by, $lowlabel, $highlabel ) = split( m!/!, $self->opts );
            $by = 1 unless ($by > 0 and int($by) == $by);
            $highlabel //= "";
            $lowlabel //= "";

            push @items, [ $from, "$lowlabel $from" ];
            for (my $at=$from+$by; $at<=$to-$by; $at+=$by) {
                push @items, [$at, $at]; # note: fake itemid, doesn't matter, but needed to be unique
            }
            push @items, [ $to, "$highlabel $to" ];


            for my $item (@items) {
                # note: itid can be fake
                my ($itid, $item) = @$item;

                LJ::Poll->clean_poll(\$item);

                # displaying a radio or checkbox
                if ($do_form) {
                    my $qvalue = $preval{$qid} || '';
                    $prevanswer = $clearanswers ? 0 : $qvalue =~ /\b$itid\b/;
                    $ret .= LJ::html_check({ 'type' => $self->type, 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                             'value' => $itid, 'id' => "pollq-$pollid-$qid-$itid",
                                             'selected' => $prevanswer });
                    $ret .= " <label for='pollq-$pollid-$qid-$itid'>$item</label><br />";
                    next;
                }

                # displaying results
                my $count = ( defined $itid ) ? $itvotes{$itid} || 0 : 0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);

                # did the user viewing this poll choose this option? If so, mark it
                my $qvalue = $preval{$qid} || '';
                my $answered = ( $qvalue =~ /\b$itid\b/ ) ? "*" : "";

                $ret .= "<tr valign='middle'><td align='right'>$item</td><td>";
                $ret .= LJ::img( 'poll_left', '', { style => 'vertical-align:middle' } );
                $ret .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle; height: 14px;' height='14' width='$width' alt='' />";
                $ret .= LJ::img( 'poll_right', '', { style => 'vertical-align:middle' } );
                $ret .= "<b>$count</b> ($percent%) $answered</td></tr>";
 
            }

            $ret .= "</table>";
         }

        $ret .= "</div></div>";

 #####################
        return $ret;
}




1;