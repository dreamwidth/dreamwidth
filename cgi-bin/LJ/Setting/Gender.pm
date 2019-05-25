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

package LJ::Setting::Gender;
use base 'LJ::Setting';
use strict;
use warnings;

sub as_html {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    # show the one just posted, else the default one.
    my $gender = $class->get_arg( $args, "gender" )
        || $u->prop("gender");

    return
          "<label for='${key}gender'>"
        . $class->ml('.setting.gender.question')
        . "</label>"
        . LJ::html_select(
        {
            'name'     => "${key}gender",
            'id'       => '${key}gender',
            'class'    => 'select',
            'selected' => $gender || 'U'
        },
        'F' => $class->ml('/manage/profile/index.bml.gender.female'),
        'M' => $class->ml('/manage/profile/index.bml.gender.male'),
        'O' => $class->ml('/manage/profile/index.bml.gender.other'),
        'U' => $class->ml('/manage/profile/index.bml.gender.unspecified')
        ) . $class->errdiv( $errs, "gender" );
}

sub should_render {
    my ( $class, $u ) = @_;

    return $u->is_individual;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "gender" );
    $class->errors( access => $class->ml('.setting.gender.error.wrongtype') )
        unless $u->is_individual;
    $class->errors( gender => $class->ml('.setting.gender.error.invalid') )
        unless $val =~ /^[UMFO]$/;
    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $gen = $class->get_arg( $args, "gender" );
    return 1 if $gen eq ( $u->prop('gender') || "U" );

    $gen = "" if $gen eq "U";
    $u->set_prop( "gender", $gen );
    $u->invalidate_directory_record;
}

1;

