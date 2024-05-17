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

package LJ::Setting::EmailPosting;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $LJ::EMAIL_POST_DOMAIN && $u && $u->is_personal ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.emailposting.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $ret = '';

    if ( $u->can_emailpost ) {
        $ret .= '<p>' . $class->ml('setting.emailposting.note') . '</p>';
        $ret .= "<a href='$LJ::SITEROOT/manage/emailpost'>";
        $ret .= $class->ml('setting.emailposting.manage') . "</a>";
    }
    else {
        $ret .= $class->ml('setting.emailposting.notavailable');
        if ( LJ::is_enabled('payments') ) {
            $ret .= " "
                . $class->ml(
                'setting.emailposting.notavailable.upgrade',
                { aopts => "href='$LJ::SHOPROOT'" }
                );
        }
    }

    return $ret;
}

1;
