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

package LJ::Setting::Display::Email;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return $u->is_validated ? "change_email" : "validate_email";
}

sub actionlink {
    my ( $class, $u ) = @_;

    my $text =
          $u->is_identity && !$u->email_raw
        ? $class->ml('setting.display.email.actionlink.set')
        : $class->ml('setting.display.email.actionlink.change');
    return "<a href='$LJ::SITEROOT/changeemail?authas=" . $u->user . "'>$text</a>";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.email.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $email = $u->email_raw;

    if ( $u->is_identity && !$email ) {
        return "";
    }
    elsif ( $u->email_status eq "A" ) {
        return "$email " . $class->ml('setting.display.email.option.validated');
    }
    else {
        return "$email "
            . $class->ml( 'setting.display.email.option.notvalidated',
            { aopts => "href='$LJ::SITEROOT/register?authas=" . $u->user . "'" } );
    }
}

1;
