#!/usr/bin/perl
#
# DW::BusinessRules::Pay
#
# This package contains functions to convert Paid to Premium Paid time
#   and vice-versa as needed when applying or removing paid time
#
# Authors:
#      Ryan Southwell <teshiron@chaosfire.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::BusinessRules::Pay::DWS;

use strict;

use base 'DW::BusinessRules::Pay';

use Carp qw/ confess /;

use constant SECS_IN_DAY     => 86400;
use constant CONVERSION_RATE => 0.7;

################################################################################
#
# DW::BusinessRules::Pay::convert
#
# Converts paid to premium paid time at a rate of 70% for day and second values,
# and a rate of 21 days for each whole month (also 70%).  Converts premium paid
# to paid time at a rate of 1/70% (approx 143% or 42.8 days per month).
#
# ARGUMENTS: from_type, dest_type, months, days, seconds
#
#   from_type   required    type of paid time being converted
#   dest_type   required    destination account type
#
# At least one of months, days, or seconds must be supplied. If more than one
# time field is supplied, the fields will be added together before conversion.
#
# RETURN: appropriate amount of paid time in seconds
#
sub convert {
    my ( $from_type, $dest_type, $months, $days, $seconds ) = @_;

    confess "invalid paid time type $from_type"
        unless $from_type =~ /^(?:premium|paid)$/;

    confess "invalid destination account type $dest_type"
        unless $dest_type =~ /^(?:premium|paid)$/;

    confess "redundant conversion from $from_type to $dest_type"
        if $from_type eq $dest_type;

    confess "no amount of time was specified for conversion"
        unless $months || $days || $seconds;

    if ( $from_type eq 'paid' and $dest_type eq 'premium' ) {    # paid to premium

        # first, convert any seconds value supplied
        $seconds = int( $seconds * CONVERSION_RATE ) if $seconds;

        # convert individual days to seconds and add on
        $seconds += int( $days * CONVERSION_RATE * SECS_IN_DAY ) if $days;

        # convert months to seconds and add on
        #   A 30-day month is assumed as per existing business logic
        $seconds += int( $months * 30 * CONVERSION_RATE * SECS_IN_DAY ) if $months;

    }
    else {    # premium to paid

        # again, first with the seconds.
        # remember that dividing by a fraction is the same as multiplying by
        #   the reciprocal, so dividing by CONVERSION_RATE is the inverse function.
        $seconds = int( $seconds / CONVERSION_RATE ) if $seconds;

        # then the days
        $seconds += int( $days / CONVERSION_RATE * SECS_IN_DAY ) if $days;

        # then the months
        $seconds += int( $months * 30 / CONVERSION_RATE * SECS_IN_DAY ) if $months;

    }

    return $seconds;

}

1;
