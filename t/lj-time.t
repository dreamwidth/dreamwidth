# t/lj-time.t
#
# Test calendar calculations and date conversions in LJ::Time.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use lib "$ENV{LJHOME}/cgi-bin";

use HTTP::Date ();
use POSIX qw( tzset );
use Test::More;

use LJ::Time;

subtest 'calendar calculations' => sub {
    is( LJ::days_in_month(0), undef, 'missing month has no length' );
    is( LJ::days_in_month(2), 29,    'unknown year allows February 29' );
    is( LJ::days_in_month( 2, 2023 ), 28, 'common year has 28 days in February' );
    is( LJ::days_in_month( 2, 2024 ), 29, 'leap year has 29 days in February' );
    is( LJ::days_in_month( 2, 1900 ), 28, 'century not divisible by 400 is a common year' );
    is( LJ::days_in_month( 2, 2000 ), 29, 'century divisible by 400 is a leap year' );
    is( LJ::days_in_month(4), 30, 'April has 30 days' );
    is( LJ::day_of_week( 2024, 2, 29 ), 4,     'February 29, 2024 was a Thursday' );
    is( LJ::day_of_week( 2023, 2, 29 ), undef, 'invalid calendar date has no weekday' );
};

subtest 'MySQL and S2 date conversion' => sub {
    is( LJ::mysqldate_to_time( undef,        1 ), undef,      'missing date has no timestamp' );
    is( LJ::mysqldate_to_time( '2024/02/29', 1 ), undef,      'reject a malformed date' );
    is( LJ::mysqldate_to_time( '0000-00-00', 1 ), undef,      'reject the MySQL zero date' );
    is( LJ::mysqldate_to_time( '2024-02-29', 1 ), 1709164800, 'date alone uses midnight UTC' );
    is( LJ::mysqldate_to_time( '2024-02-29 12:34', 1 ),
        1709210040, 'omitted seconds default to zero' );
    is( LJ::mysqldate_to_time( '2024-02-29 12:34:56', 1 ),
        1709210096, 'parse the complete datetime' );
    is( LJ::mysqldate_to_time( '2023-02-31', 1 ),
        1677542400, 'clamp the day to the end of February' );
    is(
        LJ::alldatepart_s2('2024-02-29 12:34:56'),
        '2024 02 29 12 34 56 4',
        'S2 date parts include the UTC weekday after seconds'
    );
};

subtest 'UTC and local MySQL times' => sub {
    local $ENV{TZ} = 'EST5';
    tzset();

    is( LJ::mysqldate_to_time('1970-01-01'), 18000,
        'local midnight is five hours after the epoch' );
    is( LJ::mysqldate_to_time( '1970-01-01', 1 ), 0, 'UTC midnight is the epoch' );
    is( LJ::mysql_time( 0, 1 ), '1970-01-01 00:00:00', 'format the epoch in UTC' );
    is( LJ::mysql_time(0), '1969-12-31 19:00:00', 'local time rolls back into the previous day' );
    is( LJ::mysql_date( 0, 1 ), '1970-01-01', 'UTC date' );
    is( LJ::mysql_date(0), '1969-12-31', 'local date' );
};
tzset();

subtest 'wire date formats' => sub {
    my $http_date = 'Sun, 06 Nov 1994 08:49:37 GMT';
    is( LJ::http_to_time($http_date),   784111777,  'parse an HTTP date' );
    is( LJ::http_to_time('not a date'), undef,      'reject an invalid HTTP date' );
    is( LJ::time_to_http(784111777),    $http_date, 'format an HTTP date' );
    is(
        LJ::time_to_cookie(0),
        'Thursday, 01-Jan-1970 00:00:00 GMT',
        'format the epoch as a cookie expiration'
    );
    is( LJ::time_to_w3c( 0, 'Z' ),     '1970-01-01T00:00:00Z',      'format an explicit UTC time' );
    is( LJ::time_to_w3c( 0, '-0530' ), '1970-01-01T00:00:00-05:30', 'format a numeric offset' );
};

subtest 'age changes on the birthday' => sub {
    my $now  = time();
    my $week = 7 * 24 * 60 * 60;
    my ( $past_day, $past_month, $past_year ) = ( gmtime( $now - $week ) )[ 3, 4, 5 ];
    my ( $next_day, $next_month, $next_year ) = ( gmtime( $now + $week ) )[ 3, 4, 5 ];

    is( LJ::calc_age( $past_year + 1900 - 40, $past_month + 1, $past_day ), 40, 'birthday passed' );
    is( LJ::calc_age( $next_year + 1900 - 40, $next_month + 1, $next_day ), 39,
        'birthday pending' );
    is( LJ::calc_age( 0, 1, 1 ), undef, 'missing birth year has no age' );
};

my @bootstrap = grep { m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC );
is_deeply( \@bootstrap, [], 'ljlib.pl was not loaded' );

done_testing();
