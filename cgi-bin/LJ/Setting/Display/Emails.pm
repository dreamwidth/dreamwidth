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

package LJ::Setting::Display::Emails;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.emails.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    return
        "<a href='$LJ::SITEROOT/tools/emailmanage'>"
        . $class->ml('setting.display.emails.option') . "</a>";
}

1;
