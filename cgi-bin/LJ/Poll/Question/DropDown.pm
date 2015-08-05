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

sub doform {
    my ($self, $preval, $clearanswers) = @_;
    my $ret = '';
    my $prevanswer;
    my %preval = %$preval;
    my $qid = $self->pollqid;
    my $pollid = $self->pollid;
            #### drop-down list
            my @optlist = ('', '');
            foreach my $it ($self->poll->question($qid)->items) {
                my $itid  = $it->{pollitid};
                my $item  = $it->{item};
                LJ::Poll->clean_poll(\$item);
                push @optlist, ($itid, $item);
            }
            $prevanswer = $clearanswers ? 0 : $preval{$qid};
            $ret .= LJ::html_select({ 'name' => "pollq-$qid", 'class'=>"poll-$pollid",
                                      'selected' => $prevanswer }, @optlist);
        return $ret;
}


1;