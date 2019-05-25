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

package LJ::Widget::TagCloud;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { () }

# pass in tags => [$tag1, $tag2, ...]
# tags are of the form { tagname => { url => $url, value => $value } }
sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $tagsref = delete $opts{tags};

    return '' unless $tagsref;

    return LJ::tag_cloud( $tagsref, \%opts );
}

1;
