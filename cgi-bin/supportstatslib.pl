#!/usr/bin/perl
#
#   This library is used by Support Stats.
#
#   In particular, it's used by the following pages:
#   - htdocs/admin/support/dept.bml
#   - htdocs/admin/support/individual.bml
#
#   This library doesn't have any DB access routines.
#   All DB access routines are in supportlib.pl
#

use strict;
package LJ::Support::Stats;
use vars qw($ALL_CATEGORIES_ID);

use Carp qw(croak);
use DateTime;

# Constants
$ALL_CATEGORIES_ID = -1;

# <LJFUNC>
# name: LJ::Support::Stats::filter_support_by_category
# des: Filter Support by Category ID.
# args: support
# des-support: HashRef of Support Rows indexed by Support ID.
# info: Used by dept.bml and individual.bml under
#       htdocs/admin/support/.
#       All DB access routines are in supportlib.pl.
# Return: Filtered HashRef of Support Rows.
# </LJFUNC>
sub filter_support_by_category {
    my($support_hashref, $category_id_parm) = @_;

    return $support_hashref if $category_id_parm == $ALL_CATEGORIES_ID;

    my %filtered_support = ();
    while (my($support_id, $support) = each %{$support_hashref}) {
        $filtered_support{$support_id} = $support
            if $support->{spcatid} == $category_id_parm;
    }

    return \%filtered_support;
}

# <LJFUNC>
# name: LJ::Support::Stats::date_formatter
# des: Format a date
# args: year, month, day
# des-year: Four digit year (e.g. 2001)
# des-month: One-based numeric month: 1-12
# des-day: One-based numeric day: 1-31
# info: Used by dept.bml and individual.bml under
#       htdocs/admin/support/.
#       All DB access routines are in supportlib.pl.
# Return: Date formatted as follows: YYYY-MM-DD
# </LJFUNC>
sub date_formatter {
    croak('Not enough parameters') if @_ < 3;
    my($year, $month, $day) = @_;
    my $date = sprintf("%04d-%02d-%02d", $year, $month, $day);
    return $date;
}

# <LJFUNC>
# name: LJ::Support::Stats::comma_formatter
# des: Format a number with commas
# args: number
# des-number: number to commafy.
# info: Used by dept.bml and individual.bml under
#       htdocs/admin/support/.
#       All DB access routines are in supportlib.pl.
# Return: Number with commas inserted.
# </LJFUNC>
sub comma_formatter {
    my $number = shift or croak('No parameter for comma_formatter');
    1 while ($number =~ s/([-+]?\d+)(\d\d\d\.?)(?!\d)/$1,$2/);
    return $number;
};


# <LJFUNC>
# name: LJ::Support::Stats::percent_formatter
# des: Format a percentage: Take integer portion and append percent sign.
# args: percent
# des-percent: Number to format as a percentage.
# info: Used by dept.bml and individual.bml under
#       htdocs/admin/support/.
#       All DB access routines are in supportlib.pl.
# Return: Formatted percentage.
# </LJFUNC>
sub percent_formatter {
    my $percent = shift;
    $percent = int($percent) . '%';
    return $percent;
};

# <LJFUNC>
# name: LJ::Support::Stats::get_grains_from_seconds
# des: Determine the grains (day/week/month/year) of given a date
# args: seconds
# des-seconds: Seconds since Unix epoch.
# info: Used by dept.bml and individual.bml under
#       htdocs/admin/support/.
#       All DB access routines are in supportlib.pl.
# Return: HashRef of Grains.
# </LJFUNC>
sub get_grains_from_seconds {
    my $seconds_since_epoch = shift or croak('No parameter specified');

    my $date = LJ::mysql_time($seconds_since_epoch);

    my %grain;
    $grain{grand} = 'Grand';
    $grain{day}   = substr($date, 0, 10);
    $grain{month} = substr($date, 0,  7);
    $grain{year}  = substr($date, 0,  4);

    # Get week of Support Ticket
    my $dt = DateTime->from_epoch( epoch => $seconds_since_epoch );
    my($week_year, $week_number) = $dt->week;
    $grain{week} = $week_year . ' - Week #' . sprintf('%02d', $week_number);

    return \%grain;
}


1;
