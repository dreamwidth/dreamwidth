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

package LJ::Setting::Birthday;
use base 'LJ::Setting';
use strict;
use warnings;

sub as_html {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;
    my $ret;

    $ret .= "<label for='${key}month'>" . $class->ml('.setting.birthday.question') . "</label>";
    my %bdpart;
    if ( $u->{bdate} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/ ) {
        ( $bdpart{year}, $bdpart{month}, $bdpart{day} ) = ( $1, $2, $3 );
        if ( $bdpart{year} eq "0000" ) { $bdpart{year} = ""; }
        if ( $bdpart{day} eq "00" )    { $bdpart{day}  = ""; }
    }
    $ret .= LJ::html_select(
        {
            'name'     => "${key}month",
            'id'       => "${key}month",
            'class'    => "select",
            'selected' => int( $bdpart{month} )
        },
        '', '',
        map { $_, LJ::Lang::month_long_ml($_) } ( 1 .. 12 )
    ) . " ";

    $ret .= LJ::html_text(
        {
            'name'      => "${key}day",
            'value'     => $bdpart{day},
            'class'     => 'text',
            'size'      => '3',
            'maxlength' => '2'
        }
    ) . " ";
    $ret .= LJ::html_text(
        {
            'name'      => "${key}year",
            'value'     => $bdpart{year},
            'class'     => 'text',
            'size'      => '5',
            'maxlength' => '4'
        }
    );

    $ret .= $class->errdiv( $errs, "month" );
    $ret .= $class->errdiv( $errs, "day" );
    $ret .= $class->errdiv( $errs, "year" );

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $month = $class->get_arg( $args, "month" ) || 0;
    my $day   = $class->get_arg( $args, "day" )   || 0;
    my $year  = $class->get_arg( $args, "year" )  || 0;
    my $this_year = ( localtime() )[5] + 1900;
    my $err_count = 0;
    local $BML::ML_SCOPE = "/manage/profile/index.bml";

    if ( $year && $year < 100 ) {
        $class->errors( "year" => LJ::Lang::ml('.error.year.notenoughdigits') );
        $err_count++;
    }

    if ( $year && $year >= 100 && ( $year < 1890 || $year > $this_year ) ) {
        $class->errors( "year" => LJ::Lang::ml('.error.year.outofrange') );
        $err_count++;
    }

    if ( $month && ( $month < 1 || $month > 12 ) ) {
        $class->errors( "month" => LJ::Lang::ml('.error.month.outofrange') );
        $err_count++;
    }

    if ( $day && ( $day < 1 || $day > 31 ) ) {
        $class->errors( "day" => LJ::Lang::ml('.error.day.outofrange') );
        $err_count++;
    }

    if ( $err_count == 0 && $day > LJ::days_in_month( $month, $year ) ) {
        $class->errors( "day" => LJ::Lang::ml('.error.day.notinmonth') );
    }

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $month = $class->get_arg( $args, "month" ) || 0;
    my $day   = $class->get_arg( $args, "day" )   || 0;
    my $year  = $class->get_arg( $args, "year" )  || 0;

    my %update = ( 'bdate' => sprintf( "%04d-%02d-%02d", $year, $month, $day ), );
    $u->update_self( \%update );

    # for the directory
    my $sidx_bday = sprintf( "%02d-%02d", $month, $day );
    $sidx_bday = "" if !$sidx_bday || $sidx_bday =~ /00/;
    $u->set_prop( 'sidx_bday', $sidx_bday );
    $u->invalidate_directory_record;
    $u->set_next_birthday;
}

1;
