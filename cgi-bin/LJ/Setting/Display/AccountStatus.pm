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

package LJ::Setting::Display::AccountStatus;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    if ( $u->is_deleted || $u->is_visible ) {
        return "delete_journal";
    }
    elsif ( $u->is_suspended || $u->is_readonly ) {
        return "suspended_journal";
    }

    return "";
}

sub actionlink {
    my ( $class, $u ) = @_;

    if ( $u->is_deleted ) {
        return
              "<a href='$LJ::SITEROOT/accountstatus?authas="
            . $u->user . "'>"
            . $class->ml('setting.display.accountstatus.actionlink.undelete') . "</a>";
    }
    elsif ( $u->is_suspended || $u->is_readonly ) {
        return $class->ml(
            'setting.display.accountstatus.actionlink.contactabuse',
            { aopts => "href='$LJ::SITEROOT/abuse/report'" }
        );
    }
    elsif ( $u->is_visible ) {
        return
              "<a href='$LJ::SITEROOT/accountstatus?authas="
            . $u->user . "'>"
            . $class->ml('setting.display.accountstatus.actionlink.delete') . "</a>";
    }

    return "";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.accountstatus.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    # locked, purged, and renamed users can't log in, so will never see this
    if ( $u->is_deleted ) {
        my $daysleft = ( 86400 * 30 - ( time() - $u->statusvisdate_unix ) ) / 86400;
        if ( $daysleft <= 0 ) {
            return $class->ml('setting.display.accountstatus.option.deleted.timeup');
        }
        else {
            return $class->ml( 'setting.display.accountstatus.option.deleted',
                { num => POSIX::ceil($daysleft) } );
        }
    }
    elsif ( $u->is_suspended ) {
        return $class->ml('setting.display.accountstatus.option.suspended');
    }
    elsif ( $u->is_memorial ) {
        return $class->ml('setting.display.accountstatus.option.memorial');
    }
    elsif ( $u->is_readonly ) {
        return $class->ml('setting.display.accountstatus.option.readonly');
    }
    else {
        return $class->ml('setting.display.accountstatus.option.active');
    }
}

1;
