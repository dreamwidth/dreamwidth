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

package LJ::Setting::UserMessaging;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u->is_person && LJ::is_enabled('user_messaging');
}

sub label {
    my $class = shift;
    return $class->ml( 'setting.usermessaging.label', { siteabbrev => $LJ::SITENAMEABBREV } );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $usermsg = $class->get_arg( $args, "usermsg" ) || $u->opt_usermsg;

    my @options = (
        "Y" => $class->ml('setting.usermessaging.opt.y'),
        "F" => $class->ml('setting.usermessaging.opt.f'),
        "M" => $class->ml('setting.usermessaging.opt.m'),
        "N" => $class->ml('setting.usermessaging.opt.n'),
    );

    my $ret;

    $ret .= "<label for='${key}usermsg'>";
    $ret .= $class->ml('setting.usermessaging.option');
    $ret .= "</label> ";

    $ret .= LJ::html_select(
        {
            name     => "${key}usermsg",
            id       => "${key}usermsg",
            selected => $usermsg,
        },
        @options
    );

    $ret .= "<p class='details'>";
    $ret .= $class->ml( 'setting.usermessaging.option.note', { sitename => $LJ::SITENAMESHORT } );
    $ret .= "</p>";

    my $errdiv = $class->errdiv( $errs, "usermsg" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "usermsg" );

    $class->errors( usermsg => $class->ml('setting.usermessaging.error.invalid') )
        unless $val =~ /^[MFNY]$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "usermsg" );

    $u->set_prop( opt_usermsg => $val );

    return 1;
}

1;
