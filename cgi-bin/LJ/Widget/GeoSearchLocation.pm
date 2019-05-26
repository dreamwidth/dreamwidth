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

package LJ::Widget::GeoSearchLocation;

use strict;
use base qw(LJ::Widget::Location);

sub render_body {
    my $class = shift;
    my %opts  = (
        'skip_timezone' => 1,
        @_
    );
    return $class->SUPER::render_body(%opts);
}

# do not call handle_post() of base class here
sub handle_post {
}

1;
