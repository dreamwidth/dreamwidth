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

package LJ::Widget::SubmitRequest::Support;

use strict;
use base qw(LJ::Widget::SubmitRequest LJ::Widget);
use Carp qw(croak);

sub text_done {
    my ($class, %opts) = @_;

    my $ret;

    $ret .= "<div class='highlight-box' style='float: right; width: 300px;'>";
    $ret .= "<?h2 " . $class->ml('/support/submit.bml.help.header') . " h2?>";
    $ret .= "<?p " . $class->ml('/support/submit.bml.help.text', { aopts => "href='$LJ::SITEROOT/support/help'" }) . " p?>";
    $ret .= "</div>";

    $ret .= $class->SUPER::text_done(%opts);

    return $ret;
}

1;
