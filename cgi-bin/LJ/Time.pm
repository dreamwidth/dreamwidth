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

package LJ;
use strict;

use Time::Local ();

# <LJFUNC>
# name: LJ::days_in_month
# class: time
# des: Figures out the number of days in a month.
# args: month, year?
# des-month: Month
# des-year: Year.  Necessary for February.  If undefined or zero, function
#           will return 29.
# returns: Number of days in that month in that year.
# </LJFUNC>
sub days_in_month
{
    my ($month, $year) = @_;
    return unless $month;  # not a mind reader

    if ($month == 2)
    {
        return 29 unless $year;  # assume largest
        if ($year % 4 == 0)
        {
          # years divisible by 400 are leap years
          return 29 if ($year % 400 == 0);

          # if they're divisible by 100, they aren't.
          return 28 if ($year % 100 == 0);

          # otherwise, if divisible by 4, they are.
          return 29;
        }
    }
    return ((31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[$month-1]);
}

sub day_of_week
{
    my ($year, $month, $day) = @_;
    my $time = eval { Time::Local::timelocal(0,0,0,$day,$month-1,$year) };
    return undef if $@;
    return (localtime($time))[6];
}

# <LJFUNC>
# class: time
# name: LJ::http_to_time
# des: Converts HTTP date to Unix time.
# info: Wrapper around HTTP::Date::str2time.
#       See also [func[LJ::time_to_http]].
# args: string
# des-string: HTTP Date.  See RFC 2616 for format.
# returns: integer; Unix time.
# </LJFUNC>
sub http_to_time {
    my $string = shift;
    return HTTP::Date::str2time($string);
}

sub mysqldate_to_time {
    my ($string, $gmt) = @_;
    return undef unless $string =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d)(?::(\d\d))?)?$/;
    my ($y, $mon, $d, $h, $min, $s) = ($1, $2, $3, $4, $5, $6);

    # return early if we were given "0000-00-00"
    return undef if "$y-$mon-$d" eq "0000-00-00";

    # these need to be set to zero if undefined, to avoid warnings
    $h   ||= 0;
    $min ||= 0;
    $s   ||= 0;

    my $calc = sub {
        $gmt ?
            Time::Local::timegm($s, $min, $h, $d, $mon-1, $y) :
            Time::Local::timelocal($s, $min, $h, $d, $mon-1, $y);
    };

    # try to do it.  it'll die if the day is bogus
    my $ret = eval { $calc->(); };
    return $ret unless $@;

    # then fix the day up, if so.
    my $max_day = LJ::days_in_month($mon, $y);
    $d = $max_day if $d > $max_day;
    return $calc->();
}

# <LJFUNC>
# class: time
# name: LJ::time_to_http
# des: Converts a Unix time to a HTTP date.
# info: Wrapper around HTTP::Date::time2str to make an
#       HTTP date (RFC 1123 format)  See also [func[LJ::http_to_time]].
# args: time
# des-time: Integer; Unix time.
# returns: String; RFC 1123 date.
# </LJFUNC>
sub time_to_http {
    my $time = shift;
    return HTTP::Date::time2str($time);
}

# <LJFUNC>
# name: LJ::time_to_cookie
# des: Converts Unix time to format expected in a Set-Cookie header.
# args: time
# des-time: unix time
# returns: string; Date/Time in format expected by cookie.
# </LJFUNC>
sub time_to_cookie {
    my $time = shift;
    $time = time() unless defined $time;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
    $year+=1900;

    my @day = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    return sprintf("$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
                   $mday, $year, $hour, $min, $sec);
}

# http://www.w3.org/TR/NOTE-datetime
# http://www.w3.org/TR/xmlschema-2/#dateTime
sub time_to_w3c {
    my ($time, $ofs) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);

    $mon++;
    $year += 1900;

    $ofs =~ s/([\-+]\d\d)(\d\d)/$1:$2/;
    $ofs = 'Z' if $ofs =~ /0000$/;
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02d$ofs",
                   $year, $mon, $mday,
                   $hour, $min, $sec);
}

# args: time in seconds from epoch; boolean for gmt instead of localtime
# returns: date and time in ISO format
sub mysql_time
{
    my ($time, $gmt) = @_;
    $time = time() unless defined $time;
    my @ltime = $gmt ? gmtime($time) : localtime($time);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                   $ltime[5]+1900,
                   $ltime[4]+1,
                   $ltime[3],
                   $ltime[2],
                   $ltime[1],
                   $ltime[0]);
}

# args: time in seconds from epoch; boolean for gmt instead of localtime
# returns: date in ISO format
sub mysql_date {
    my ( $time, $gmt ) = @_;
    $time = time() unless defined $time;
    my @ltime = $gmt ? gmtime( $time ) : localtime( $time );
    return sprintf( "%04d-%02d-%02d",
                    $ltime[5]+1900, $ltime[4]+1, $ltime[3] );
}

# <LJFUNC>
# name: LJ::alldatepart_s2
# des: Gets date in MySQL format, produces s2dateformat.
# class: time
# args:
# des-:
# info: s2 dateformat is: yyyy mm dd hh mm ss day_of_week
# returns:
# </LJFUNC>
sub alldatepart_s2
{
    my $time = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday) =
        gmtime(LJ::mysqldate_to_time($time, 1));
    return
        sprintf("%04d %02d %02d %02d %02d %02d %01d",
                $year+1900,
                $mon+1,
                $mday,
                $hour,
                $min,
                $sec,
                $wday);
}

# Given a year, month, and day; calculate the age in years compared to now. May return a negative number or
# zero if called in such a way as would cause those.

sub calc_age {
    my ($year, $mon, $day) = @_;

    $year += 0; # Force all the numeric context, so 0s become false.
    $mon  += 0;
    $day  += 0;

    my ($cday, $cmon, $cyear) = (gmtime)[3,4,5];
    $cmon  += 1;    # Normalize the month to 1-12
    $cyear += 1900; # Normalize the year

    return unless $year;
    my $age = $cyear - $year;

    return $age unless $mon;

    # Sometime this year they will be $age, subtract one if we haven't hit their birthdate yet.
    $age -= 1 if $cmon < $mon;
    return $age unless $day;

    # Sometime this month they will be $age, subtract one if we haven't hit their birthdate yet.
    $age -= 1 if ($cday < $day && $cmon == $mon);

    return $age;
}



1;
