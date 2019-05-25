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

package LJ::Setting::CommentScreening;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "screening";
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentscreening.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $commentscreening =
        $class->get_arg( $args, "commentscreening" ) || $u->prop("opt_whoscreened");

    my @options = (
        N => $class->ml('setting.commentscreening.option.select.none'),
        R => $class->ml('setting.commentscreening.option.select.anon'),
        F => $u->is_community
        ? $class->ml('setting.commentscreening.option.select.nonmembers')
        : $class->ml('setting.commentscreening.option.select.nonfriends'),
        A => $class->ml('setting.commentscreening.option.select.all'),
    );

    my $select = LJ::html_select(
        {
            name     => "${key}commentscreening",
            id       => "${key}commentscreening",
            selected => $commentscreening,
        },
        @options
    );

    return
          "<label for='${key}commentscreening'>"
        . $class->ml( 'setting.commentscreening.option', { options => $select } )
        . "</label>";
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "commentscreening" );
    $val = "N" unless $val =~ /^[NRFA]$/;

    $u->set_prop( opt_whoscreened => $val );

    return 1;
}

1;
