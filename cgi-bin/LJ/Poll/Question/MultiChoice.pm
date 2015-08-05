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

1;