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

package LJ::Setting::BirthdayDisplay;
use base 'LJ::Setting';
use strict;
use warnings;

sub as_html {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;
    my $ret;

    $ret .=
          "<label for='${key}opt_showbday'>"
        . $class->ml('.setting.birthdaydisplay.question')
        . "</label>";
    $u->prop('opt_showbday') = "D" unless $u->prop('opt_showbday') =~ m/^(D|F|N|Y)$/;
    $ret .= LJ::html_select(
        {
            'name'     => "${key}opt_showbday",
            'id'       => "${key}opt_showbday",
            'class'    => "select",
            'selected' => $u->prop('opt_showbday')
        },
        "N" => LJ::Lang::ml('/manage/profile/index.bml.show.birthday.nothing'),
        "D" => LJ::Lang::ml('/manage/profile/index.bml.show.birthday.day'),
        "Y" => LJ::Lang::ml('/manage/profile/index.bml.show.birthday.year'),
        "F" => LJ::Lang::ml('/manage/profile/index.bml.show.birthday.full')
    );
    $ret .= $class->errdiv( $errs, "opt_showbday" );

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $opt_showbday = $class->get_arg( $args, "opt_showbday" );
    $class->errors( "opt_showbday" => $class->ml('.setting.birthdaydisplay.error.invalid') )
        unless $opt_showbday =~ /^[DFNY]$/;
    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my %bdpart;
    if ( $u->{bdate} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/ ) {
        ( $bdpart{year}, $bdpart{month}, $bdpart{day} ) = ( $1, $2, $3 );
        if ( $bdpart{year} eq "0000" ) { $bdpart{year} = ""; }
        if ( $bdpart{day} eq "00" )    { $bdpart{day}  = ""; }
    }

    my $opt_showbday = $class->get_arg( $args, "opt_showbday" );
    $u->set_prop( 'opt_showbday', $opt_showbday );

    # if they're showing their full birthdate or the year, then
    # include them in age-based searches
    my $sidx_bdate = "";
    if ( $opt_showbday =~ /^[FY]$/ ) {
        if ( $bdpart{year} ) {
            $sidx_bdate = sprintf( "%04d-%02d-%02d", map { $bdpart{$_} } qw(year month day) );
        }
    }
    $u->set_prop( 'sidx_bdate', $sidx_bdate );
    $u->invalidate_directory_record;
}

1;
