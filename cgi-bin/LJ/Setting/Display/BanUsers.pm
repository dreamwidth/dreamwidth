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

package LJ::Setting::Display::BanUsers;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "banusers";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.banusers.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $remote   = LJ::get_remote();
    my $getextra = $remote && $remote->user ne $u->user ? "?authas=" . $u->user : "";

    my $ret = "<a href='$LJ::SITEROOT/manage/banusers$getextra'>";
    $ret .=
          $u->is_community
        ? $class->ml('setting.display.banusers.option.comm')
        : $class->ml('setting.display.banusers.option.self');
    $ret .= "</a>";

    return $ret;
}

1;
