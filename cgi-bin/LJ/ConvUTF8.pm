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

# this is a small wrapper around Unicode::MapUTF8, just so we can lazily-load it easier
# with Class::Autouse, and so we have a central place to init its charset aliases.
# and in the future if we switch transcoding packages, we can just do it here.
package LJ::ConvUTF8;

use strict;
use warnings;
use Unicode::MapUTF8 ();

BEGIN {
    # declare some charset aliases
    # we need this at least for cases when the only name supported
    # by MapUTF8.pm isn't recognized by browsers
    # note: newer versions of MapUTF8 know these
    {
        my %alias = (
            'windows-1251' => 'cp1251',
            'windows-1252' => 'cp1252',
            'windows-1253' => 'cp1253',
        );
        foreach ( keys %alias ) {
            next if Unicode::MapUTF8::utf8_supported_charset($_);
            Unicode::MapUTF8::utf8_charset_alias( $_, $alias{$_} );
        }
    }
}

sub load {
    1;
}

sub supported_charset {
    my ( $class, $charset ) = @_;
    return Unicode::MapUTF8::utf8_supported_charset($charset);
}

sub from_utf8 {
    my ( $class, $from_enc, $str ) = @_;
    return Unicode::MapUTF8::from_utf8( { -string => $str, -charset => $from_enc } );
}

sub to_utf8 {
    my ( $class, $to_enc, $str ) = @_;
    return Unicode::MapUTF8::to_utf8( { -string => $str, -charset => $to_enc } );
}

1;

