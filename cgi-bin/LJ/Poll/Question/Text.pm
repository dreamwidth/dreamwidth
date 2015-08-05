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

package LJ::Poll::Question::Text;
use strict;
use parent qw/LJ::Poll::Question/;


sub show_individual_result{
    my ($self, $preval) = @_;
    my $ret = '';
    my $qid = $self->pollqid;
    my $pollid = $self->pollid;
    if ( $preval->{$qid} ) {
        LJ::Poll->clean_poll( \$preval->{$qid} );
        $ret .= "<br />" . BML::ml('poll.useranswer', { "answer" => $preval->{$qid} } );
    }
    
    my $prevanswer;

    return $ret;
}


sub doform {
    my ($self, $preval, $clearanswers) = @_;
    my $ret = '';
    my $qid = $self->pollqid;
    my $pollid = $self->pollid;
    my ($size, $max) = split(m!/!, $self->opts);
    my $prevanswer = $clearanswers ? "" : $preval->{$qid};

    $ret .= LJ::html_text({ 'size' => $size, 'maxlength' => $max, 'class'=>"poll-$pollid",
                                'name' => "pollq-$qid", 'value' => $prevanswer });
        return $ret;
}

sub has_sub_items {0}
sub previewing_snippet {
    my $self = shift;
    my $ret = '';

    my $type = $self->type;
    my $opts = $self->opts;
    
    my ($size, $max) = split(m!/!, $opts);
    $ret .= LJ::html_text({ 'size' => $size, 'maxlength' => $max });
    return $ret;
}

sub process_tag_options {
    my ($opts, $qopts,$err) = @_;
    my $size = 35;
    my $max = 255;
    if (defined $opts->{'size'}) {
        if ($opts->{'size'} > 0 &&
            $opts->{'size'} <= 100)
        {
            $size = $opts->{'size'}+0;
        } else {
            return $err->('poll.error.badsize2');
        }
    }
    if (defined $opts->{'maxlength'}) {
        if ($opts->{'maxlength'} > 0 &&
            $opts->{'maxlength'} <= 255)
        {
            $max = $opts->{'maxlength'}+0;
        } else {
            return $err->('poll.error.badmaxlength');
        }
    }

    $qopts->{'opts'} = "$size/$max";
    return $qopts;
}
1;
