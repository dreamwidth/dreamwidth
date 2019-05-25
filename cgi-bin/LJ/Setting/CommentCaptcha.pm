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

package LJ::Setting::CommentCaptcha;
use base 'LJ::Setting';
use DW::Captcha;
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return 0 unless DW::Captcha->site_enabled;
    return $u && !$u->is_identity ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentcaptcha.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $commentcaptcha =
        $class->get_arg( $args, "commentcaptcha" ) || $u->prop("opt_show_captcha_to");

    my @options = (
        N => $class->ml('setting.commentcaptcha.option.select.none'),
        R => $class->ml('setting.commentcaptcha.option.select.anon'),
        F => $u->is_community
        ? $class->ml('setting.commentcaptcha.option.select.nonmembers')
        : $class->ml('setting.commentcaptcha.option.select.nonfriends'),
        A => $class->ml('setting.commentcaptcha.option.select.all'),
    );

    my $ret =
          "<label for='${key}commentcaptcha'>"
        . $class->ml('setting.commentcaptcha.option')
        . "</label> ";
    $ret .= LJ::html_select(
        {
            name     => "${key}commentcaptcha",
            id       => "${key}commentcaptcha",
            selected => $commentcaptcha,
        },
        @options
    );

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "commentcaptcha" );
    $val = "N" unless $val =~ /^[NRFA]$/;

    $u->set_prop( opt_show_captcha_to => $val );

    return 1;
}

1;
