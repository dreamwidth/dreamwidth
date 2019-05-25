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
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BusinessRules::Pay;

use strict;

use base 'DW::BusinessRules';

use Carp qw/ confess /;

use constant SECS_IN_DAY => 86400;

################################################################################
#
# DW::BusinessRules::Pay::convert
#
# Default function to allow conversion of paid time between different types
# of paid account. This default implementation simply converts the passed
# arguments to seconds and returns without further modification.  This can be
# overridden as needed with site-specific logic. Assumes 30-day months.
#
# ARGUMENTS: from_type, dest_type, months, days, seconds
#
#   from_type   optional    type of paid time being converted; ignored
#   dest_type   optional    destination account type; ignored
#
# At least one of months, days, or seconds must be supplied. If more than one
# time field is supplied, the fields will be added together before conversion.
#
# RETURN: appropriate amount of paid time in seconds
#
sub convert {
    my ( $from_type, $dest_type, $months, $days, $seconds ) = @_;

    confess "no amount of time was specified for conversion"
        unless $months || $days || $seconds;

    $seconds += $days * SECS_IN_DAY;
    $seconds += $months * 30 * SECS_IN_DAY;

    return $seconds;
}

DW::BusinessRules::install_overrides( __PACKAGE__, qw( convert ) );
1;
