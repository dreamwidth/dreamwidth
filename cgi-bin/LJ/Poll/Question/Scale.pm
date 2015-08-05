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

sub doform {
    my ($self, $preval, $clearanswers) = @_;
    my $ret = '';
    my $prevanswer;
    my %preval = %$preval;
    my $qid = $self->pollqid;
    my $pollid = $self->pollid;


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
    } else {
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


 #####################
        return $ret;
}


1;