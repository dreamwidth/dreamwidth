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

package LJ::Setting::SearchInclusion;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "search_engines";
}

sub label {
    my ( $class, $u ) = @_;

    return $class->ml('setting.searchinclusion.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $searchinclusion =
        $class->get_arg( $args, "searchinclusion" ) || $u->prop("opt_blockrobots");

    my $ret = LJ::html_check(
        {
            name     => "${key}searchinclusion",
            id       => "${key}searchinclusion",
            value    => 1,
            selected => $searchinclusion ? 1 : 0,
        }
    );
    $ret .= " <label for='${key}searchinclusion'>";
    $ret .=
          $u->is_community
        ? $class->ml('setting.searchinclusion.option.comm')
        : $class->ml('setting.searchinclusion.option.self');
    $ret .= "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "searchinclusion" ) ? 1 : 0;
    $u->set_prop( opt_blockrobots => $val );

    return 1;
}

1;
