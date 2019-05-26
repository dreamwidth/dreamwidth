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

package LJ::Setting::MinSecurity;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ( $class, $u ) = @_;

    return "minsecurity_full";
}

sub label {
    my $class = shift;

    return $class->ml('setting.minsecurity.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $minsecurity = $class->get_arg( $args, "minsecurity" ) || $u->prop("newpost_minsecurity");

    my @options = (
        ""      => $class->ml('setting.minsecurity.option.select.public2'),
        friends => $u->is_community ? $class->ml('setting.minsecurity.option.select.members2')
        : $class->ml('setting.minsecurity.option.select.accesslist'),
        private => $u->is_community ? $class->ml('setting.minsecurity.option.select.admins')
        : $class->ml('setting.minsecurity.option.select.private2')
    );

    my $ret =
        "<label for='${key}minsecurity'>" . $class->ml('setting.minsecurity.option') . "</label> ";
    $ret .= LJ::html_select(
        {
            name     => "${key}minsecurity",
            id       => "${key}minsecurity",
            selected => $minsecurity,
        },
        @options
    );

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "minsecurity" );
    $val = "" unless $val =~ /^(friends|private)$/;

    $u->set_prop( newpost_minsecurity => $val );

    return 1;
}

1;
