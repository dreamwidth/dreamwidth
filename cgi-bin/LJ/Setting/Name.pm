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

package LJ::Setting::Name;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;
use LJ::Global::Constants;

sub current_value {
    my ( $class, $u ) = @_;
    return $u->{name} || "";
}

sub text_size { 40 }

sub question {
    my $class = shift;

    return $class->ml('.setting.name.question');
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg($args);

    # for testing:
    if ( $LJ::T_FAKE_SETTINGS_RULES && $val =~ /\`bad/ ) {
        $class->errors( "txt" => "T-FAKE-ERROR: bogus value" );
    }

    unless ( length $val ) {
        $class->errors( "txt" => "You must specify a name" );
    }

    1;
}

sub save_text {
    my ( $class, $u, $txt ) = @_;
    $txt = LJ::text_trim( $txt, LJ::BMAX_NAME, LJ::CMAX_NAME );
    return 0 unless $u && $u->update_self( { name => $txt } );
    LJ::load_userid( $u->userid, "force" );
    return 1;
}

1;
