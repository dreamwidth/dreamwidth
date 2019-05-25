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

package LJ::Setting::StyleMine;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return !$u || $u->is_community ? 0 : 1;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "comment_page_styles_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.stylemine.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $stylemine = $class->get_arg( $args, "stylemine" ) || $u->prop('opt_stylemine');

    my $ret = LJ::html_check(
        {
            name     => "${key}stylemine",
            id       => "${key}stylemine",
            value    => 1,
            selected => $stylemine ? 1 : 0,
        }
    );
    $ret .= " <label for='${key}stylemine'>" . $class->ml('setting.stylemine.option2') . "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "stylemine" ) ? 1 : 0;
    $u->set_prop( opt_stylemine => $val );

    return 1;
}

1;
