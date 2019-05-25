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

package LJ::Setting::EmailFormat;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return !$u || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "comment_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.emailformat.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $emailformat = $class->get_arg( $args, "emailformat" ) || $u->prop("opt_htmlemail");

    my $ret;
    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}emailformat",
            id       => "${key}emailformat_html",
            value    => "Y",
            selected => $emailformat eq "Y" ? 1 : 0,
        }
        )
        . "<label for='${key}emailformat_html' class='radiotext'>"
        . $class->ml('setting.emailformat.option.html')
        . "</label>";
    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}emailformat",
            id       => "${key}emailformat_plaintext",
            value    => "N",
            selected => $emailformat eq "N" ? 1 : 0,
        }
        )
        . "<label for='${key}emailformat_plaintext' class='radiotext'>"
        . $class->ml('setting.emailformat.option.plaintext')
        . "</label>";

    my $errdiv = $class->errdiv( $errs, "emailformat" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "emailformat" );

    $class->errors( emailformat => $class->ml('setting.emailformat.error.invalid') )
        unless $val =~ /^[YN]$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "emailformat" );
    $u->update_self( { opt_htmlemail => $val } );

    return 1;
}

1;
